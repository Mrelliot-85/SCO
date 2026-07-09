unit SCO_CashLogyService;
interface
uses
  System.SysUtils, System.Classes, IdTCPClient;
type
  TCashLogyResult = record
    OK: Boolean;
    StatusText: string;
    RawResponse: string;
  end;
  TCashLogyService = class
  private
    FHost: string;
    FPort: Integer;
    FTimeout: Integer;
    function SendCommand(const Cmd: string; AReadTimeout: Integer = 5000): string;
    function SendPaymentCommand(const Cmd: string; AReadTimeout: Integer): string;
    function IsPaymentIntermediate(const Response: string): Boolean;
    function IsPaymentSuccess(const Response: string): Boolean;
    function IsPaymentBusy(const Response: string): Boolean;
    function WaitForPaymentCompletion(AReadTimeout, AmountCent: Integer): string;
    function IsChargePaid(const Response: string; AmountCent: Integer): Boolean;
    procedure Log(const S: string);
  public
    constructor Create(const AHost: string; APort: Integer);
    function Init: TCashLogyResult;
    function Status: TCashLogyResult;
    function MoneyStatus: TCashLogyResult;
    function CoinStatus: TCashLogyResult;
    function Backoffice: TCashLogyResult;
    function AddChange: TCashLogyResult;
    function EndSession: TCashLogyResult;
    function WaitStatus: TCashLogyResult;
    function Command(const Cmd, SuccessText: string; AReadTimeout: Integer = 5000): TCashLogyResult;
    function Pay(Amount: Double): TCashLogyResult;
  end;
implementation
uses
  Winapi.Windows, System.IOUtils, IdGlobal;
constructor TCashLogyService.Create(const AHost: string; APort: Integer);
begin
  inherited Create;
  FHost := Trim(AHost);
  if FHost = '' then
    FHost := '127.0.0.1';
  FPort := APort;
  if FPort <= 0 then
    FPort := 8092;
  FTimeout := 60000;
end;
procedure TCashLogyService.Log(const S: string);
var
  LogDir, LogFile: string;
begin
  try
    LogDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'logs';
    ForceDirectories(LogDir);
    LogFile := IncludeTrailingPathDelimiter(LogDir) + 'payment.log';
    TFile.AppendAllText(
      LogFile,
      FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' CASHLOGY ' + S + sLineBreak,
      TEncoding.UTF8
    );
  except
    // Logging darf niemals einen Zahlvorgang abbrechen.
  end;
end;

function TCashLogyService.IsPaymentIntermediate(const Response: string): Boolean;
var
  U: string;
begin
  U := UpperCase(Trim(Response));
  Result :=
    (U = '#CASHLOGY_INTERMEDIATE_NO_FINAL#') or
    (Pos('#0#2.', U) = 1);
end;

function TCashLogyService.IsPaymentSuccess(const Response: string): Boolean;
var
  U: string;
begin
  U := UpperCase(Trim(Response));
  Result :=
    (Pos('OK', U) > 0) or
    (Pos('SUCCESS', U) > 0) or
    (Pos('BEZAHLT', U) > 0) or
    (Pos('PAYMENT OK', U) > 0) or
    (Pos('#OK#', U) > 0);
end;

function TCashLogyService.IsPaymentBusy(const Response: string): Boolean;
var
  U: string;
begin
  U := UpperCase(Trim(Response));
  Result :=
    (U = '') or
    (Pos('#ER:BUSY#', U) = 1) or
    (Pos('BUSY', U) > 0) or
    IsPaymentIntermediate(U);
end;

function TCashLogyService.WaitForPaymentCompletion(AReadTimeout, AmountCent: Integer): string;
var
  StartTick: Cardinal;
  R, U: string;
begin
  Result := '';
  StartTick := GetTickCount;
  Log('PAYMENT WAIT START');

  while GetTickCount - StartTick < Cardinal(AReadTimeout) do
  begin
    Sleep(2000);
    R := SendCommand('#Q#', 5000);
    U := UpperCase(Trim(R));
    Log('PAYMENT WAIT STATUS ' + R);

    if IsChargePaid(R, AmountCent) then
      Exit(R);

    if Pos('#ER:BUSY#', U) = 1 then
      Continue;

    if Pos('#0#2.', U) = 1 then
      Continue;

    if (U <> '') and (not IsPaymentBusy(U)) then
      Exit(R);
  end;

  Result := '#CASHLOGY_PAYMENT_TIMEOUT#';
end;
function TCashLogyService.IsChargePaid(const Response: string; AmountCent: Integer): Boolean;
var
  Parts: TStringList;
  Code: string;
  AutoPaid, ReturnedAmount, ManualPaid: Integer;
begin
  Result := False;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := '#';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := Trim(Response);

    if Parts.Count < 5 then
      Exit;

    Code := UpperCase(Trim(Parts[1]));
    if (Code = 'WR:CANCEL') or (Pos('ER:', Code) = 1) then
      Exit;

    if (Code <> '0') and (Pos('WR:', Code) <> 1) then
      Exit;

    AutoPaid := StrToIntDef(Trim(Parts[2]), 0);
    ReturnedAmount := StrToIntDef(Trim(Parts[3]), 0);
    ManualPaid := StrToIntDef(Trim(Parts[4]), 0);

    Result := (AutoPaid + ManualPaid - ReturnedAmount) >= AmountCent;
  finally
    Parts.Free;
  end;
end;
function TCashLogyService.SendCommand(const Cmd: string; AReadTimeout: Integer): string;
var
  TCP: TIdTCPClient;
  StartTick: Cardinal;
begin
  Result := '';
  TCP := TIdTCPClient.Create(nil);
  try
    TCP.Host := FHost;
    TCP.Port := FPort;
    TCP.ConnectTimeout := 5000;
    TCP.ReadTimeout := AReadTimeout;
    Log('TCP CONNECT ' + FHost + ':' + IntToStr(FPort));
    TCP.Connect;
    Log('TCP SEND ' + Cmd);
    TCP.IOHandler.Write(Cmd + #13#10, IndyTextEncoding_UTF8);

    StartTick := GetTickCount;
    while TCP.Connected and (GetTickCount - StartTick < Cardinal(AReadTimeout)) do
    begin
      TCP.IOHandler.CheckForDataOnSource(100);
      if not TCP.IOHandler.InputBufferIsEmpty then
      begin
        Result := Trim(TCP.IOHandler.InputBufferAsString(IndyTextEncoding_UTF8));
        Break;
      end;
      Sleep(50);
    end;

    Log('TCP RESPONSE ' + Result);
  finally
    if TCP.Connected then
      TCP.Disconnect;
    TCP.Free;
  end;
end;

function TCashLogyService.SendPaymentCommand(const Cmd: string; AReadTimeout: Integer): string;
var
  TCP: TIdTCPClient;
  StartTick: Cardinal;
  Response, U: string;
  HadIntermediate: Boolean;
  HadSent: Boolean;
begin
  Result := '';
  Response := '';
  HadIntermediate := False;
  HadSent := False;
  TCP := TIdTCPClient.Create(nil);
  try
    try
      TCP.Host := FHost;
      TCP.Port := FPort;
      TCP.ConnectTimeout := 5000;
      TCP.ReadTimeout := 1000;
      Log('TCP PAYMENT CONNECT ' + FHost + ':' + IntToStr(FPort));
      TCP.Connect;
      Log('TCP PAYMENT SEND ' + Cmd);
      TCP.IOHandler.Write(Cmd + #13#10, IndyTextEncoding_UTF8);
      HadSent := True;

      StartTick := GetTickCount;
      while TCP.Connected and (GetTickCount - StartTick < Cardinal(AReadTimeout)) do
    begin
      TCP.IOHandler.CheckForDataOnSource(250);
      if not TCP.IOHandler.InputBufferIsEmpty then
      begin
        Response := Trim(TCP.IOHandler.InputBufferAsString(IndyTextEncoding_UTF8));
        Result := Response;
        Log('TCP PAYMENT RESPONSE ' + Response);
        U := UpperCase(Response);

        if (Pos('#0#2.', U) = 1) then
        begin
          HadIntermediate := True;
          Continue;
        end;

        Break;
      end;
      Sleep(100);
    end;

      U := UpperCase(Result);
      if HadIntermediate and ((Result = '') or (Pos('#0#2.', U) = 1)) then
        Result := '#CASHLOGY_INTERMEDIATE_NO_FINAL#';
    except
      on E: Exception do
      begin
        Log('TCP PAYMENT ERROR ' + E.Message);
        if HadSent or HadIntermediate then
          Result := '#CASHLOGY_INTERMEDIATE_NO_FINAL#'
        else
          raise;
      end;
    end;
  finally
    if TCP.Connected then
      TCP.Disconnect;
    TCP.Free;
  end;
end;

function TCashLogyService.Command(const Cmd, SuccessText: string; AReadTimeout: Integer): TCashLogyResult;
begin
  Result.OK := False;
  Result.StatusText := '';
  Result.RawResponse := '';
  try
    Result.RawResponse := SendCommand(Cmd, AReadTimeout);
    Result.OK := Result.RawResponse <> '';
    if Result.OK then
      Result.StatusText := SuccessText + ': ' + Result.RawResponse
    else
      Result.StatusText := 'CashLogy Connector antwortet nicht auf ' + Cmd;
  except
    on E: Exception do
    begin
      Result.OK := False;
      Result.RawResponse := E.ClassName;
      Result.StatusText := 'CashLogy TCP nicht erreichbar (' + FHost + ':' + IntToStr(FPort) + '). ' +
        'Bitte pruefen: Connector laeuft nur einmal, TCP-Port ist frei und im Connector korrekt eingestellt. Fehler: ' + E.Message;
      Log('ERROR COMMAND ' + Cmd + ' ' + E.Message);
    end;
  end;
end;
function TCashLogyService.MoneyStatus: TCashLogyResult;
begin
  Result := Command('#T#', 'Geldbestand gelesen', 8000);
end;
function TCashLogyService.CoinStatus: TCashLogyResult;
begin
  Result := Command('#Y#', 'Stueckelung gelesen', 8000);
end;
function TCashLogyService.Backoffice: TCashLogyResult;
begin
  Result := Command('#G#1#1#1#1#1#1#1#1#1#1#1#1#1#', 'Backoffice am Zahlautomaten geoeffnet', 8000);
end;
function TCashLogyService.AddChange: TCashLogyResult;
begin
  Result := Command('#A#2#', 'Wechselgeld hinzufuegen gestartet', 8000);
end;
function TCashLogyService.EndSession: TCashLogyResult;
begin
  Result := Command('#J#', 'CashLogy Vorgang beendet', 8000);
end;
function TCashLogyService.WaitStatus: TCashLogyResult;
begin
  Result := Command('#Q#', 'CashLogy Status gelesen', 8000);
end;
function TCashLogyService.Init: TCashLogyResult;
begin
  Result := Command('#I#', 'CashLogy initialisiert', 8000);
end;
function TCashLogyService.Status: TCashLogyResult;
begin
  Result := WaitStatus;
end;
function TCashLogyService.Pay(Amount: Double): TCashLogyResult;
var
  AmountCent: Integer;
  Cmd, U: string;
begin
  Result.OK := False;
  Result.StatusText := '';
  Result.RawResponse := '';
  AmountCent := Round(Amount * 100);
  Cmd := Format('#C#1#1#%d#1#17000#1500#0#1#0#0#', [AmountCent]);
  FTimeout := 180000;
  Result.RawResponse := SendPaymentCommand(Cmd, FTimeout);
  Result.OK := False;

  if IsPaymentIntermediate(Result.RawResponse) then
    Result.RawResponse := WaitForPaymentCompletion(FTimeout, AmountCent);

  U := UpperCase(Result.RawResponse);
  // Ein Bereitschaftsstatus oder ein allgemeines 'OK' bestaetigt noch keine
  // Bargeldzahlung. Erfolgreich ist nur die Betragsantwort des Connectors.
  Result.OK := IsChargePaid(Result.RawResponse, AmountCent);

  if Result.OK then
    Result.StatusText := 'Barzahlung erfolgreich: ' + Result.RawResponse
  else if Result.RawResponse = '#CASHLOGY_PAYMENT_TIMEOUT#' then
    Result.StatusText := 'Zeitueberschreitung bei Barzahlung. Bitte Zahlung am Zahlautomaten pruefen.'
  else if Result.RawResponse <> '' then
    Result.StatusText := 'Barzahlung nicht erfolgreich: ' + Result.RawResponse
  else
    Result.StatusText := 'CashLogy Connector antwortet nicht auf ' + Cmd;
end;

end.














