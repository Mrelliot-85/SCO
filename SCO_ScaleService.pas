unit SCO_ScaleService;

interface

function ScaleReadWeightJson: string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  Winapi.Windows,
  IdTCPClient,
  SCO_CONFIG,
  SCO_Logger;

type
  TScaleResult = record
    OK: Boolean;
    Stable: Boolean;
    Weight: Double;
    Gross: Double;
    Tara: Double;
    Net: Double;
    UnitText: string;
    AlibiNo: string;
    RawText: string;
    MessageText: string;
  end;

function JS(const S: string): string;
begin
  Result := S;
  Result := StringReplace(Result, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
end;

function FloatJson(Value: Double): string;
begin
  Result := StringReplace(FormatFloat('0.000', Value), ',', '.', []);
end;

function JsonResult(const R: TScaleResult): string;
begin
  Result :=
    '{' +
    '"ok":' + IfThen(R.OK, 'true', 'false') + ',' +
    '"stable":' + IfThen(R.Stable, 'true', 'false') + ',' +
    '"weight":' + FloatJson(R.Weight) + ',' +
    '"gross":' + FloatJson(R.Gross) + ',' +
    '"tara":' + FloatJson(R.Tara) + ',' +
    '"net":' + FloatJson(R.Net) + ',' +
    '"alibi":"' + JS(R.AlibiNo) + '",' +
    '"unit":"' + JS(R.UnitText) + '",' +
    '"raw":"' + JS(R.RawText) + '",' +
    '"message":"' + JS(R.MessageText) + '"' +
    '}';
end;

function JsonError(const Msg, Raw: string): string;
var
  R: TScaleResult;
begin
  R.OK := False;
  R.Stable := False;
  R.Weight := 0;
  R.Gross := 0;
  R.Tara := 0;
  R.Net := 0;
  R.UnitText := 'kg';
  R.AlibiNo := '';
  R.RawText := Raw;
  R.MessageText := Msg;
  Result := JsonResult(R);
end;

function PortDeviceName(const ComPort: string): string;
begin
  Result := Trim(ComPort);
  if Result = '' then
    Result := 'COM3';
  if Pos('\\.\', Result) <> 1 then
    Result := '\\.\' + Result;
end;

function ReadSoehnleSerial(const ComPort: string; Baud, TimeoutMS: Integer;
  const RequestText: string): string;
var
  H: THandle;
  DCB: TDCB;
  Timeouts: TCommTimeouts;
  Req: TBytes;
  Buf: TBytes;
  BytesDone: DWORD;
  Started: Cardinal;
  Chunk: string;
begin
  Result := '';
  H := CreateFile(PChar(PortDeviceName(ComPort)), GENERIC_READ or GENERIC_WRITE,
    0, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if H = INVALID_HANDLE_VALUE then
    RaiseLastOSError;
  try
    SetupComm(H, 4096, 4096);
    PurgeComm(H, PURGE_RXCLEAR or PURGE_TXCLEAR);

    FillChar(DCB, SizeOf(DCB), 0);
    DCB.DCBlength := SizeOf(DCB);
    if not GetCommState(H, DCB) then
      RaiseLastOSError;
    DCB.BaudRate := Baud;
    DCB.ByteSize := 8;
    DCB.Parity := NOPARITY;
    DCB.StopBits := ONESTOPBIT;
    DCB.Flags := DCB.Flags or 1; // binary mode
    if not SetCommState(H, DCB) then
      RaiseLastOSError;

    FillChar(Timeouts, SizeOf(Timeouts), 0);
    Timeouts.ReadIntervalTimeout := 50;
    Timeouts.ReadTotalTimeoutMultiplier := 0;
    Timeouts.ReadTotalTimeoutConstant := TimeoutMS;
    Timeouts.WriteTotalTimeoutMultiplier := 0;
    Timeouts.WriteTotalTimeoutConstant := TimeoutMS;
    if not SetCommTimeouts(H, Timeouts) then
      RaiseLastOSError;

    Req := TEncoding.ASCII.GetBytes(RequestText);
    if Length(Req) > 0 then
      if not WriteFile(H, Req[0], Length(Req), BytesDone, nil) then
        RaiseLastOSError;

    SetLength(Buf, 256);
    Started := GetTickCount;
    repeat
      BytesDone := 0;
      if not ReadFile(H, Buf[0], Length(Buf), BytesDone, nil) then
        RaiseLastOSError;
      if BytesDone > 0 then
      begin
        Chunk := TEncoding.ASCII.GetString(Buf, 0, BytesDone);
        Result := Result + Chunk;
        if (Pos(#10, Result) > 0) or (Pos(#13, Result) > 0) then
          Break;
        // Einige 3820-Konfigurationen senden keinen Zeilenabschluss.
        // Mit der Einheit ist der Gewichtswert vollstaendig empfangen.
        if Pos(' KG', UpperCase(Result)) > 0 then
          Break;
      end;
    until Integer(GetTickCount - Started) >= TimeoutMS;
  finally
    CloseHandle(H);
  end;
end;

function ReadSoehnleTcp(const Host: string; Port, TimeoutMS: Integer;
  const RequestText: string): string;
var
  Client: TIdTCPClient;
begin
  Result := '';
  Client := TIdTCPClient.Create(nil);
  try
    Client.Host := Host;
    Client.Port := Port;
    Client.ConnectTimeout := TimeoutMS;
    Client.ReadTimeout := TimeoutMS;
    Client.Connect;
    Client.IOHandler.Write(RequestText);
    Result := Client.IOHandler.ReadLn('', TimeoutMS);
  finally
    Client.Free;
  end;
end;

function ExtractNumberText(const S: string): string;
var
  I: Integer;
  Started: Boolean;
begin
  Result := '';
  Started := False;
  for I := 1 to Length(S) do
  begin
    if S[I] in ['0'..'9', '+', '-', ',', '.'] then
    begin
      Result := Result + S[I];
      Started := True;
    end
    else if Started then
      Break;
  end;
end;

function ParseScaleNumber(const NumberText: string; out Value: Double): Boolean;
var
  FS: TFormatSettings;
  S: string;
begin
  FS := TFormatSettings.Create;
  FS.DecimalSeparator := '.';
  S := StringReplace(NumberText, ',', '.', [rfReplaceAll]);
  Result := TryStrToFloat(S, Value, FS);
end;

function ExtractAlibiNo(const Line: string): string;
var
  I: Integer;
begin
  Result := '';
  if (Length(Line) < 2) or (UpCase(Line[1]) <> 'A') then
    Exit;
  I := 2;
  while (I <= Length(Line)) and CharInSet(Line[I], ['0'..'9']) do
  begin
    Result := Result + Line[I];
    Inc(I);
  end;
end;

function TryWeightAfterMarker(const Line: string; Marker: Char; out Value: Double): Boolean;
var
  I: Integer;
  NumberText: string;
begin
  Result := False;
  Value := 0;
  for I := 1 to Length(Line) do
  begin
    if UpCase(Line[I]) = UpCase(Marker) then
    begin
      NumberText := ExtractNumberText(Copy(Line, I + 1, MaxInt));
      if (NumberText <> '') and ParseScaleNumber(NumberText, Value) then
      begin
        Result := True;
        Exit;
      end;
    end;
  end;
end;
function ParseSoehnleLine(const Raw: string; out R: TScaleResult): Boolean;
var
  Line, Status, Rest, NumberText: string;
  P: Integer;
  ParsedWeight: Double;
begin
  R.OK := False;
  R.Stable := False;
  R.Weight := 0;
  R.Gross := 0;
  R.Tara := 0;
  R.Net := 0;
  R.UnitText := 'kg';
  R.AlibiNo := '';
  R.RawText := Raw;
  R.MessageText := 'Waage gelesen';
  Result := False;

  Line := Trim(StringReplace(StringReplace(Raw, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Line = '' then
  begin
    R.MessageText := 'Keine Antwort der Waage.';
    Exit;
  end;

  R.AlibiNo := ExtractAlibiNo(Line);
  Status := Copy(Line, 1, 4);
  R.Stable := (Length(Status) >= 3) and (Status[3] = '1');

  TryWeightAfterMarker(Line, 'G', R.Gross);
  TryWeightAfterMarker(Line, 'T', R.Tara);
  TryWeightAfterMarker(Line, 'N', R.Net);

  Rest := Line;
  if (Length(Line) >= 7) and (Line[1] in ['0'..'9']) then
    Rest := Trim(Copy(Line, 7, MaxInt));

  P := Pos('NH', Rest);
  if P = 0 then P := Pos('N', Rest);
  if P = 0 then P := Pos('BH', Rest);
  if P = 0 then P := Pos('B', Rest);
  if P = 0 then P := Pos('PT', Rest);
  if P = 0 then P := Pos('T', Rest);
  if P > 0 then
    Rest := Trim(Copy(Rest, P + 1, MaxInt));

  NumberText := ExtractNumberText(Rest);
  if NumberText = '' then
  begin
    R.MessageText := 'Gewicht konnte nicht gelesen werden.';
    Exit;
  end;

  if not ParseScaleNumber(NumberText, ParsedWeight) then
  begin
    R.MessageText := 'Gewicht konnte nicht umgerechnet werden.';
    Exit;
  end;

  if Pos(' g', LowerCase(Rest)) > 0 then
    ParsedWeight := ParsedWeight / 1000;

  if R.Net <= 0 then
    R.Net := ParsedWeight;
  if R.Gross <= 0 then
    R.Gross := R.Net + R.Tara;
  R.Weight := R.Net;
  R.UnitText := 'kg';

  R.OK := True;
  Result := True;
end;
function ScaleReadWeightJson: string;
var
  Raw: string;
  R: TScaleResult;
  TimeoutMS: Integer;
begin
  SCOConfig.Load;
  if not SCOConfig.ScaleActive then
  begin
    Result := JsonError('Waage ist in der Config nicht aktiv.', '');
    Exit;
  end;

  TimeoutMS := SCOConfig.ScaleTimeoutMS;
  if TimeoutMS <= 0 then
    TimeoutMS := 2500;

  try
    LogTransaction('SCALE READ vendor=' + SCOConfig.ScaleVendor +
      ' mode=' + SCOConfig.ScaleMode);

    if SameText(SCOConfig.ScaleMode, 'tcp') or SameText(SCOConfig.ScaleMode, 'ethernet') then
      Raw := ReadSoehnleTcp(SCOConfig.ScaleHost, SCOConfig.ScaleTCPPort, TimeoutMS,
        SCOConfig.ScaleRequest)
    else
      Raw := ReadSoehnleSerial(SCOConfig.ScaleComPort, SCOConfig.ScaleBaud, TimeoutMS,
        SCOConfig.ScaleRequest);

    if not ParseSoehnleLine(Raw, R) then
    begin
      LogTransaction('SCALE READ FAIL raw=' + Raw + ' msg=' + R.MessageText);
      Result := JsonResult(R);
      Exit;
    end;

    LogTransaction('SCALE READ OK weight=' + FloatToStr(R.Weight) + ' raw=' + Raw);
    LogEichamtWeighing('SCALE_READ', 0, '', R.Gross, R.Tara, R.Net, R.AlibiNo, Raw, 'stable=' + BoolToStr(R.Stable, True));
    Result := JsonResult(R);
  except
    on E: Exception do
    begin
      LogError('SCALE READ ERROR: ' + E.ClassName + ' - ' + E.Message);
      Result := JsonError('Waage nicht erreichbar: ' + E.Message, Raw);
    end;
  end;
end;

end.

