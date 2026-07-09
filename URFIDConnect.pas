unit URFIDConnect;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Variants, System.Classes, System.Types,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls;

  function RFID_open(port: Integer; baudrate: LongInt): Integer; cdecl; external 'MYDLL.dll' name 'open';
function RFID_close: Integer; cdecl; external 'MYDLL.dll' name 'close';
function RFID_timeout(ms: Integer): Integer; cdecl; external 'MYDLL.dll' name 'timeout';

function PiccActivateA(
  ucMode: Byte;
  ucReqCode: Byte;
  pATQ: PByte;
  pSAK: PByte;
  pUIDLen: PByte;
  pUID: PByte
): Integer; cdecl; external 'MYDLL.dll';

type
  TForm2 = class(TForm)
    btn_connect: TButton;
    btn_sendTagID: TButton;
    btn_startauto: TButton;
    btn_stopauto: TButton;
    memo_log: TMemo;
    edit_sendTagID: TEdit;
    Btn_test: TButton;
    btn_versionTest: TButton;
    cb_hid: TCheckBox;
    Timer1: TTimer;
    Memo_tag: TMemo;
    Edit1: TEdit;
    btn_sendCommand: TButton;
    btn_taglesen: TButton;
    procedure FormCreate(Sender: TObject);
    procedure btn_connectClick(Sender: TObject);
    procedure btn_sendTagIDClick(Sender: TObject);
    procedure btn_startautoClick(Sender: TObject);
    procedure btn_stopautoClick(Sender: TObject);
    procedure Btn_testClick(Sender: TObject);
    procedure btn_versionTestClick(Sender: TObject);
    procedure cb_hidClick(Sender: TObject);
    procedure btn_sendCommandClick(Sender: TObject);
    procedure btn_taglesenClick(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);




  private
    FPort: string;
    FBaud: DWORD;
    FLastUID: string;

procedure TagIn(const S: string);
procedure TagOut(const S: string);
function ReadTagUID_COM(out AUID: string): Boolean;
function CmdToHex(const Cmd: array of Byte): string;
    procedure Log(const S: string);
    procedure TagLog(const S: string);

    function BytesToHex(const B: TBytes): string;
    function BytesToAscii(const B: TBytes; AStart, ACount: Integer): string;
    function HexToBytes(const S: string; out B: TBytes): Boolean;

    function SendComCommand(const Cmd: array of Byte; out Reply: TBytes): Boolean;

    function XorChecksum(const B: TBytes): Byte;
    function Make50Command(ACommand: Byte; const Payload: array of Byte): TBytes;

    function GetSoftwareVersion(out AVersion: string): Boolean;
    function ReadTagUID(out AUID: string): Boolean;
    function NTAGReadPage(APage: Byte; out ADataHex: string): Boolean;
    function NTAGWritePage(APage: Byte; const AText: string): Boolean;
  public
  end;

var
  Form2: TForm2;

implementation

{$R *.dfm}

const
  CMD_VERSION: array[0..5] of Byte =
    ($AA, $00, $01, $86, $87, $BB);
  CMD_SERIAL: array[0..5] of Byte =
  ($AA, $00, $01, $83, $82, $BB);
procedure TForm2.FormCreate(Sender: TObject);
begin
  FPort := 'COM4';
  FBaud := CBR_115200;
  FLastUID := '';

  Timer1.Enabled := False;
  Timer1.Interval := 700;

  memo_log.Clear;
  Memo_tag.Clear;

  Log('Bereit. Port=' + FPort + ' Baud=' + IntToStr(FBaud));
  if not FileExists(ExtractFilePath(Application.ExeName) + 'MYDLL.dll') then
  ShowMessage('MYDLL.dll fehlt');

if not FileExists(ExtractFilePath(Application.ExeName) + 'PCOMM.DLL') then
  ShowMessage('PCOMM.DLL fehlt');

if not FileExists(ExtractFilePath(Application.ExeName) + 'hidapi.dll') then
  ShowMessage('hidapi.dll fehlt');
end;

procedure TForm2.Log(const S: string);
begin
  memo_log.Lines.Add(FormatDateTime('hh:nn:ss.zzz', Now) + ' ' + S);
end;

procedure TForm2.TagLog(const S: string);
begin
  Memo_tag.Lines.Add(FormatDateTime('hh:nn:ss.zzz', Now) + ' ' + S);
end;

function TForm2.BytesToHex(const B: TBytes): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(B) do
    Result := Result + IntToHex(B[I], 2) + ' ';
  Result := Trim(Result);
end;

procedure TForm2.TagIn(const S: string);
begin
  Memo_tag.Lines.Add('>> ' + S);
end;

procedure TForm2.TagOut(const S: string);
begin
  Memo_tag.Lines.Add('<< ' + S);
end;

procedure TForm2.Timer1Timer(Sender: TObject);
var
  UID: string;
begin
  if ReadTagUID_COM(UID) then
  begin
    if UID <> FLastUID then
    begin
      FLastUID := UID;
      TagIn(UID);
    end;
  end;
end;

function TForm2.BytesToAscii(const B: TBytes; AStart, ACount: Integer): string;
var
  I, LastIdx: Integer;
begin
  Result := '';
  if (AStart < 0) or (AStart > High(B)) or (ACount <= 0) then Exit;

  LastIdx := AStart + ACount - 1;
  if LastIdx > High(B) then LastIdx := High(B);

  for I := AStart to LastIdx do
    if B[I] in [$20..$7E] then
      Result := Result + Chr(B[I])
    else
      Result := Result + '.';
end;

function TForm2.HexToBytes(const S: string; out B: TBytes): Boolean;
var
  Clean: string;
  I, N: Integer;
begin
  Result := False;
  Clean := UpperCase(S);
  Clean := StringReplace(Clean, ' ', '', [rfReplaceAll]);
  Clean := StringReplace(Clean, #13, '', [rfReplaceAll]);
  Clean := StringReplace(Clean, #10, '', [rfReplaceAll]);

  if (Clean = '') or ((Length(Clean) mod 2) <> 0) then Exit;

  SetLength(B, Length(Clean) div 2);
  for I := 0 to High(B) do
  begin
    if not TryStrToInt('$' + Copy(Clean, I * 2 + 1, 2), N) then Exit;
    B[I] := Byte(N);
  end;

  Result := True;
end;

function TForm2.CmdToHex(const Cmd: array of Byte): string;
var
  I: Integer;
begin
  Result := '';

  for I := Low(Cmd) to High(Cmd) do
    Result := Result + IntToHex(Cmd[I], 2) + ' ';

  Result := Trim(Result);
end;



function TForm2.SendComCommand(const Cmd: array of Byte; out Reply: TBytes): Boolean;
var
  h: THandle;
  DCB: TDCB;
  Timeouts: TCommTimeouts;
  Written, Readed, NeedLen, TotalRead: DWORD;
  Buf: array[0..2047] of Byte;
  StartTick: Cardinal;
  I: Integer;
begin
  Result := False;
  SetLength(Reply, 0);

  h := CreateFile(PChar('\\.\' + FPort), GENERIC_READ or GENERIC_WRITE,
                  0, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);

  if h = INVALID_HANDLE_VALUE then
  begin
    Log('Open Fehler: ' + SysErrorMessage(GetLastError));
    Exit;
  end;

  try
    SetupComm(h, 4096, 4096);

    FillChar(DCB, SizeOf(DCB), 0);
    DCB.DCBlength := SizeOf(DCB);
    GetCommState(h, DCB);

    DCB.BaudRate := FBaud; // 115200
    DCB.ByteSize := 8;
    DCB.Parity := NOPARITY;
    DCB.StopBits := ONESTOPBIT;
    DCB.Flags := 1;

    if not SetCommState(h, DCB) then
    begin
      Log('SetCommState Fehler: ' + SysErrorMessage(GetLastError));
      Exit;
    end;

    FillChar(Timeouts, SizeOf(Timeouts), 0);
    Timeouts.ReadIntervalTimeout := MAXDWORD;
    Timeouts.ReadTotalTimeoutMultiplier := 0;
    Timeouts.ReadTotalTimeoutConstant := 50;
    Timeouts.WriteTotalTimeoutMultiplier := 0;
    Timeouts.WriteTotalTimeoutConstant := 500;
    SetCommTimeouts(h, Timeouts);

    EscapeCommFunction(h, SETDTR);
    EscapeCommFunction(h, SETRTS);
    Sleep(80);

    PurgeComm(h, PURGE_RXCLEAR or PURGE_TXCLEAR);

    Log('TX: ' + CmdToHex(Cmd));

    if not WriteFile(h, Cmd[0], Length(Cmd), Written, nil) then
    begin
      Log('Write Fehler: ' + SysErrorMessage(GetLastError));
      Exit;
    end;

    FillChar(Buf, SizeOf(Buf), 0);
    TotalRead := 0;
    NeedLen := 0;
    StartTick := GetTickCount;

    repeat
      Readed := 0;
      ReadFile(h, Buf[TotalRead], SizeOf(Buf) - TotalRead, Readed, nil);

      if Readed > 0 then
      begin
        Inc(TotalRead, Readed);

        if (NeedLen = 0) and (TotalRead >= 3) then
          NeedLen := (DWORD(Buf[1]) shl 8) + Buf[2] + 5;
      end
      else
        Sleep(20);

      if (NeedLen > 0) and (TotalRead >= NeedLen) then
        Break;

    until GetTickCount - StartTick > 1500;

    if TotalRead > 0 then
    begin
      if NeedLen = 0 then
        NeedLen := TotalRead;

      SetLength(Reply, NeedLen);
      for I := 0 to NeedLen - 1 do
        Reply[I] := Buf[I];

      Log('RX: ' + BytesToHex(Reply));
      Result := True;
    end
    else
      Log('RX: keine Antwort');

  finally
    EscapeCommFunction(h, CLRDTR);
    EscapeCommFunction(h, CLRRTS);
    CloseHandle(h);
  end;
end;

function TForm2.XorChecksum(const B: TBytes): Byte;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(B) do
    Result := Result xor B[I];
end;

function TForm2.Make50Command(ACommand: Byte; const Payload: array of Byte): TBytes;
var
  I, L: Integer;
begin
  L := Length(Payload);

  SetLength(Result, 4 + L + 1);
  Result[0] := $50;
  Result[1] := 0;
  Result[2] := L;
  Result[3] := ACommand;

  for I := 0 to L - 1 do
    Result[4 + I] := Payload[I];

  Result[High(Result)] := XorChecksum(Copy(Result, 0, Length(Result) - 1));
end;

function TForm2.GetSoftwareVersion(out AVersion: string): Boolean;
var
  R: TBytes;
  PayloadLen: Integer;
begin
  AVersion := '';
  Result := SendComCommand(CMD_VERSION, R);

  if Result then
  begin
    Log('VERSION RX: ' + BytesToHex(R));

    if (Length(R) >= 6) and (R[0] = $AA) then
    begin
      PayloadLen := R[2];
      AVersion := BytesToAscii(R, 4, PayloadLen - 1);
    end;
  end;
end;

function TForm2.ReadTagUID_COM(out AUID: string): Boolean;
var
  Cmd, R: TBytes;
  UIDLen, J: Integer;
begin
  Result := False;
  AUID := '';

  // PICCACTIVATE: Reset 0A, Active-ALL/WUPA 52
  Cmd := Make50Command($22, [$0A, $52]);

  TagOut(BytesToHex(Cmd));

  if not SendComCommand(Cmd, R) then
  begin
    Log('Keine Antwort auf PICCACTIVATE 0A 52');
    Exit;
  end;

  Log('TAG RX RAW: ' + BytesToHex(R));

  if (Length(R) >= 9) and (R[0] = $50) and (R[3] = $22) then
  begin
    UIDLen := R[7];

    if (UIDLen > 0) and ((8 + UIDLen - 1) <= High(R)) then
    begin
      for J := 0 to UIDLen - 1 do
        AUID := AUID + IntToHex(R[8 + J], 2);

      Result := True;
    end;
  end;
end;

function TForm2.ReadTagUID(out AUID: string): Boolean;
var
  Cmd, R: TBytes;
  UIDLen, I: Integer;
begin
  AUID := '';

  // ISO14443A PICCActivate: 50 00 02 22 10 26 46
  Cmd := Make50Command($22, [$10, $26]);

  TagLog('TAG SUCHEN TX: ' + BytesToHex(Cmd));
  Result := SendComCommand(Cmd, R);

  if not Result then
  begin
    TagLog('TAG SUCHEN: keine Antwort');
    Exit;
  end;

  TagLog('TAG SUCHEN RX: ' + BytesToHex(R));

  if (Length(R) >= 9) and (R[0] = $50) and (R[3] = $22) then
  begin
    UIDLen := R[7];

    if (UIDLen > 0) and (8 + UIDLen - 1 <= High(R)) then
    begin
      for I := 0 to UIDLen - 1 do
        AUID := AUID + IntToHex(R[8 + I], 2);

      TagLog('UID: ' + AUID);
      Result := True;
      Exit;
    end;
  end;

  Result := False;
end;

function TForm2.NTAGReadPage(APage: Byte; out ADataHex: string): Boolean;
var
  Cmd, R: TBytes;
begin
  ADataHex := '';

  if not ReadTagUID(ADataHex) then
  begin
    TagLog('Vor READ keine Karte gefunden.');
    Result := False;
    Exit;
  end;

  // PICCTRANSFER -> NTAG READ: 30 page
  Cmd := Make50Command($2E, [$30, APage]);

  TagLog('NTAG READ PAGE ' + IntToStr(APage) + ' TX: ' + BytesToHex(Cmd));
  Result := SendComCommand(Cmd, R);

  if Result then
  begin
    ADataHex := BytesToHex(R);
    TagLog('NTAG READ RX: ' + ADataHex);
  end
  else
    TagLog('NTAG READ: keine Antwort');
end;

function TForm2.NTAGWritePage(APage: Byte; const AText: string): Boolean;
var
  Cmd, R: TBytes;
  Data: array[0..3] of Byte;
  I: Integer;
  DummyUID: string;
begin
  FillChar(Data, SizeOf(Data), 0);

  for I := 1 to 4 do
    if I <= Length(AText) then
      Data[I - 1] := Ord(AText[I])
    else
      Data[I - 1] := Ord(' ');

  if not ReadTagUID(DummyUID) then
  begin
    TagLog('Vor WRITE keine Karte gefunden.');
    Result := False;
    Exit;
  end;

  // PICCTRANSFER -> NTAG WRITE: A2 page 4 bytes
  Cmd := Make50Command($2E, [$A2, APage, Data[0], Data[1], Data[2], Data[3]]);

  TagLog('NTAG WRITE PAGE ' + IntToStr(APage) + ' TX: ' + BytesToHex(Cmd));
  Result := SendComCommand(Cmd, R);

  if Result then
    TagLog('NTAG WRITE RX: ' + BytesToHex(R))
  else
    TagLog('NTAG WRITE: keine Antwort');
end;

procedure TForm2.btn_connectClick(Sender: TObject);
var
  V: string;
begin
  memo_log.Clear;

  if GetSoftwareVersion(V) then
    Log('Reader verbunden: ' + V)
  else
    Log('Keine Antwort vom Reader.');
end;

procedure TForm2.btn_versionTestClick(Sender: TObject);
begin
  btn_connectClick(Sender);
end;

procedure TForm2.Btn_testClick(Sender: TObject);
var
  h: THandle;
  Err: DWORD;
begin
  h := CreateFile(PChar('\\.\' + FPort), GENERIC_READ or GENERIC_WRITE,
                  0, nil, OPEN_EXISTING, 0, 0);

  if h = INVALID_HANDLE_VALUE then
  begin
    Err := GetLastError;
    ShowMessage('Fehler: ' + IntToStr(Err) + sLineBreak + SysErrorMessage(Err));
  end
  else
  begin
    ShowMessage(FPort + ' geöffnet');
    CloseHandle(h);
  end;
end;

procedure TForm2.btn_startautoClick(Sender: TObject);
begin
  FLastUID := '';
  Timer1.Enabled := True;
  Log('Auto-Lesen gestartet.');
end;

procedure TForm2.btn_sendTagIDClick(Sender: TObject);
var
  DataHex: string;
begin
  Memo_tag.Clear;

  // Test: NTAG Seite 4 lesen
  NTAGReadPage(4, DataHex);
end;

procedure TForm2.btn_stopautoClick(Sender: TObject);
begin
  Timer1.Enabled := False;
  Log('Auto-Lesen gestoppt.');
end;

procedure TForm2.btn_taglesenClick(Sender: TObject);
const
  Modes: array[0..3] of Byte = ($00, $0A, $10, $26);
  Reqs: array[0..1] of Byte = ($26, $52);
var
  Ret: Integer;
  ATQ: array[0..1] of Byte;
  SAK: Byte;
  UIDLen: Byte;
  UID: array[0..15] of Byte;
  I, M, Q: Integer;
  S: string;
begin
  Memo_tag.Clear;
  memo_log.Clear;

  Ret := RFID_open(4, 115200);
  memo_log.Lines.Add('open=' + IntToStr(Ret));
  if Ret <> 0 then Exit;

  try
    RFID_timeout(2000);

    for M := Low(Modes) to High(Modes) do
      for Q := Low(Reqs) to High(Reqs) do
      begin
        FillChar(ATQ, SizeOf(ATQ), 0);
        SAK := 0;
        UIDLen := 0;
        FillChar(UID, SizeOf(UID), 0);

        Ret := PiccActivateA(Modes[M], Reqs[Q], @ATQ[0], @SAK, @UIDLen, @UID[0]);

        memo_log.Lines.Add(
          'PiccActivateA Mode=' + IntToHex(Modes[M],2) +
          ' Req=' + IntToHex(Reqs[Q],2) +
          ' Ret=' + IntToStr(Ret) +
          ' UIDLen=' + IntToStr(UIDLen) +
          ' SAK=' + IntToHex(SAK,2) +
          ' ATQ=' + IntToHex(ATQ[0],2) + ' ' + IntToHex(ATQ[1],2)
        );

        if Ret = 0 then
        begin
          S := '';
          for I := 0 to UIDLen - 1 do
            S := S + IntToHex(UID[I], 2);

          Memo_tag.Lines.Add('>> ' + S);
          Exit;
        end;
      end;
  finally
    RFID_close;
  end;
end;

procedure TForm2.btn_sendCommandClick(Sender: TObject);
var
  Cmd, R: TBytes;
begin
  Memo_tag.Clear;

  if not HexToBytes(Edit1.Text, Cmd) then
  begin
    TagLog('Ungültiger HEX-Befehl in Edit1.');
    Exit;
  end;

  TagLog('RAW TX: ' + BytesToHex(Cmd));

  if SendComCommand(Cmd, R) then
    TagLog('RAW RX: ' + BytesToHex(R))
  else
    TagLog('RAW: keine Antwort');
end;

procedure TForm2.cb_hidClick(Sender: TObject);
begin
  TagLog('HID ON/OFF wird bei deinem R855 aktuell abgelehnt. Für Lesen/Schreiben nicht weiter verwenden.');
end;

end.
