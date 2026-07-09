unit SCO_PaymentService;

interface

uses
  System.SysUtils;

type
  TSCOZahlart = (zaUnbekannt, zaEC, zaBar, zaKundenkonto, zaGutschein);

  TSCOPaymentResult = record
    OK: Boolean;
    Zahlart: string;
    MessageText: string;
    RawText: string;
  end;

  TSCOPaymentService = class
  private
    function JsonEscape(const S: string): string;
    function BoolJson(Value: Boolean): string;

    function PayZVT(Betrag: Double): TSCOPaymentResult;
    function PayCashLogy(Betrag: Double): TSCOPaymentResult;
    function PayKundenkonto(Betrag: Double): TSCOPaymentResult;
    function PayGutschein(Betrag: Double): TSCOPaymentResult;
  public
    function Pay(const Zahlart: string; Betrag: Double): TSCOPaymentResult;
    function ResultToJson(const R: TSCOPaymentResult): string;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Win.Registry,
  SCO_CONFIG,
  SCO_ZVTUtils,
  SCO_Logger,
  SCO_CashLogyService;

function TSCOPaymentService.JsonEscape(const S: string): string;
begin
  Result := S;
  Result := StringReplace(Result, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
end;

function TSCOPaymentService.BoolJson(Value: Boolean): string;
begin
  if Value then
    Result := 'true'
  else
    Result := 'false';
end;

function TSCOPaymentService.ResultToJson(const R: TSCOPaymentResult): string;
begin
  Result :=
    '{' +
    '"ok":' + BoolJson(R.OK) + ',' +
    '"zahlart":"' + JsonEscape(R.Zahlart) + '",' +
    '"message":"' + JsonEscape(R.MessageText) + '",' +
    '"raw":"' + JsonEscape(R.RawText) + '"' +
    '}';
end;

function TSCOPaymentService.Pay(const Zahlart: string; Betrag: Double): TSCOPaymentResult;
var
  Z: string;
begin
  SCOConfig.Load;

  Result.OK := False;
  Result.Zahlart := Zahlart;
  Result.MessageText := '';
  Result.RawText := '';

  if Betrag <= 0 then
  begin
    Result.MessageText := 'Ungültiger Zahlungsbetrag.';
    Exit;
  end;

  Z := LowerCase(Trim(Zahlart));

  LogPayment('PAYMENT START Zahlart=' + Z + ' Betrag=' + FormatFloat('0.00', Betrag));

  try
    if SameText(Z, 'ec') or SameText(Z, 'karte') or SameText(Z, 'zvt') then
      Result := PayZVT(Betrag)
    else if SameText(Z, 'bar') or SameText(Z, 'cash') or SameText(Z, 'cashlogy') then
      Result := PayCashLogy(Betrag)
    else if SameText(Z, 'kundenkonto') or SameText(Z, 'kundenkarte') then
      Result := PayKundenkonto(Betrag)
    else if SameText(Z, 'gutschein') then
      Result := PayGutschein(Betrag)
    else
      Result.MessageText := 'Unbekannte Zahlungsart: ' + Zahlart;

  except
    on E: Exception do
    begin
      Result.OK := False;
      Result.MessageText := 'Zahlungsfehler: ' + E.Message;
      Result.RawText := E.ClassName;
      LogPayment('PAYMENT ERROR ' + E.Message);
    end;
  end;

  LogPayment('PAYMENT END OK=' + BoolToStr(Result.OK, True) +
      ' Zahlart=' + Result.Zahlart +
      ' Message=' + Result.MessageText);
end;

function TSCOPaymentService.PayZVT(Betrag: Double): TSCOPaymentResult;
var
  Reg: TRegistry;
  BetragInCent: Integer;
  ZVTExePfad: string;
  SEInfo: TShellExecuteInfo;
  ParameterString: string;
  StartTick: Cardinal;
  TimeoutMS: Cardinal;
  Aktiv: Integer;
  ErgebnisText: string;
  TestMode: Boolean;
  TriedPaths: string;
begin
  Result.OK := False;
  Result.Zahlart := 'ec';
  Result.MessageText := 'Warte auf EC-Zahlung...';
  Result.RawText := '';

  BetragInCent := Round(Betrag * 100);
  TimeoutMS := 180000; // 3 Minuten
  TestMode := SCOConfig.DemoModus or SCOConfig.ZVT_Test;

  ForceDirectories(ExtractFilePath(ParamStr(0)) + 'ZVT\');

  Reg := TRegistry.Create(KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;

    if Reg.OpenKey('Software\GUB\ZVT', True) then
    begin
      Reg.WriteInteger('Aktiv', 1);
      Reg.WriteString('Betrag', IntToStr(BetragInCent));
      Reg.WriteString('COM', 'LAN');
      Reg.WriteString('IP', SCOConfig.ZVT_Host);
      Reg.WriteString('Port', IntToStr(SCOConfig.ZVT_Port));
      Reg.WriteString('KasseNr', IntToStr(SCOConfig.ZVT_Kasse));
      Reg.WriteString('Lizenz', SCOConfig.ZVT_Lizenz);
      Reg.WriteString('Ausgabepfad', ExtractFilePath(ParamStr(0)) + 'ZVT\');
      Reg.WriteInteger('Kassedruck', SCOConfig.ZVT_Kassedruck);
      Reg.WriteInteger('Dialog', SCOConfig.ZVT_Dialog);
      Reg.WriteInteger('dialog', SCOConfig.ZVT_Dialog);

      if TestMode then
        Reg.WriteInteger('Test', 1)
      else
        Reg.WriteInteger('Test', 0);
    end;
  finally
    Reg.Free;
  end;

  ZVTExePfad := ResolveZVTExePath(TriedPaths);

  if not FileExists(ZVTExePfad) then
  begin
    Result.MessageText := 'EasyZVT.exe wurde nicht gefunden. Bitte im Admin unter ZVT den Pfad eintragen. Geprueft:' + sLineBreak + TriedPaths;
    Exit;
  end;

  if SCOConfig.DemoModus then
    ParameterString := Format(
      'e KasseNr=%d COM=LAN IP=%s Port=%d Betrag=%d Lizenz=%s Test=1 Kassedruck=%d Ausgabepfad=%sZVT\',
      [
        SCOConfig.ZVT_Kasse,
        SCOConfig.ZVT_Host,
        SCOConfig.ZVT_Port,
        BetragInCent,
        SCOConfig.ZVT_Lizenz,
        SCOConfig.ZVT_Kassedruck,
        ExtractFilePath(ParamStr(0))
      ]
    )
  else
    ParameterString := Format(
      'e KasseNr=%d COM=LAN IP=%s Port=%d Betrag=%d Lizenz=%s Test=%d Dialog=%d Kassedruck=%d Ausgabepfad=%sZVT\',
      [
        SCOConfig.ZVT_Kasse,
        SCOConfig.ZVT_Host,
        SCOConfig.ZVT_Port,
        BetragInCent,
        SCOConfig.ZVT_Lizenz,
        Ord(TestMode),
        SCOConfig.ZVT_Dialog,
        SCOConfig.ZVT_Kassedruck,
        ExtractFilePath(ParamStr(0))
      ]
    );
  FillChar(SEInfo, SizeOf(SEInfo), 0);
  SEInfo.cbSize := SizeOf(TShellExecuteInfo);
  SEInfo.fMask := SEE_MASK_NOCLOSEPROCESS;
  SEInfo.lpFile := PChar(ZVTExePfad);
  SEInfo.lpParameters := PChar(ParameterString);
  SEInfo.nShow := SW_HIDE;

  if SCOConfig.DemoModus then
    LogPayment('ZVT DEMOMODUS AKTIV - Test=1 wird erzwungen');
  LogPayment('ZVT EXE ' + ZVTExePfad);
  LogPayment('ZVT START ' + ParameterString);

  if not ShellExecuteEx(@SEInfo) then
  begin
    Result.MessageText := 'EasyZVT.exe konnte nicht gestartet werden.';
    Exit;
  end;

  StartTick := GetTickCount;

  while True do
  begin
    Aktiv := 1;
    ErgebnisText := '';

    Reg := TRegistry.Create(KEY_READ);
    try
      Reg.RootKey := HKEY_CURRENT_USER;

      if Reg.OpenKey('Software\GUB\ZVT', False) then
      begin
        if Reg.ValueExists('Aktiv') then
          Aktiv := Reg.ReadInteger('Aktiv');

        if Reg.ValueExists('ErgebnisText') then
          ErgebnisText := Reg.ReadString('ErgebnisText');
      end;
    finally
      Reg.Free;
    end;

    if Aktiv = 0 then
    begin
      Result.RawText := ErgebnisText;

      if ErgebnisText = '' then
        ErgebnisText := 'ZVT abgeschlossen. Kein Ergebnistext vorhanden.';

      if ContainsText(ErgebnisText, 'erfolgreich') or
         ContainsText(ErgebnisText, 'genehmigt') or
         ContainsText(ErgebnisText, 'zahlung erfolgt') or
         ContainsText(ErgebnisText, 'bezahlt') or
         ContainsText(ErgebnisText, 'ok') then
      begin
        Result.OK := True;
        Result.MessageText := 'EC-Zahlung erfolgreich.';
      end
      else
      begin
        Result.OK := False;
        Result.MessageText := 'EC-Zahlung nicht erfolgreich: ' + ErgebnisText;
      end;

      Break;
    end;

    if GetTickCount - StartTick > TimeoutMS then
    begin
      Result.OK := False;
      Result.MessageText := 'Zeitüberschreitung bei EC-Zahlung.';
      Result.RawText := 'Timeout';
      Break;
    end;

    Sleep(500);
  end;
end;

function TSCOPaymentService.PayCashLogy(Betrag: Double): TSCOPaymentResult;
var
  Cash: TCashLogyService;
  R: TCashLogyResult;
begin
  Result.OK := False;
  Result.Zahlart := 'bar';
  Result.MessageText := 'Warte auf Barzahlung...';
  Result.RawText := '';

  Cash := TCashLogyService.Create(
    SCOConfig.CashLogyConnectorHost,
    SCOConfig.CashLogyConnectorPort
  );

  try
    R := Cash.Pay(Betrag);

    Result.OK := R.OK;
    Result.RawText := R.RawResponse;

    if R.OK then
      Result.MessageText := 'Barzahlung erfolgreich.'
    else if R.StatusText <> '' then
      Result.MessageText := 'Barzahlung nicht erfolgreich: ' + R.StatusText
    else
      Result.MessageText := 'Barzahlung nicht erfolgreich.';
  finally
    Cash.Free;
  end;
end;

function TSCOPaymentService.PayKundenkonto(Betrag: Double): TSCOPaymentResult;
begin
  Result.OK := False;
  Result.Zahlart := 'kundenkonto';
  Result.RawText := '';

  if not SCOConfig.PaymentKundenkarte then
  begin
    Result.MessageText := 'Zahlung per Kundenkonto ist nicht aktiviert.';
    Exit;
  end;

  // Platzhalter: später Kundenkonto prüfen / buchen
  Result.OK := True;
  Result.MessageText := 'Zahlung per Kundenkonto erfolgreich.';
end;

function TSCOPaymentService.PayGutschein(Betrag: Double): TSCOPaymentResult;
begin
  Result.OK := False;
  Result.Zahlart := 'gutschein';
  Result.RawText := '';

  if not SCOConfig.PaymentGutschein then
  begin
    Result.MessageText := 'Zahlung per Gutschein ist nicht aktiviert.';
    Exit;
  end;

  // Platzhalter: später Gutschein prüfen / einlösen
  Result.OK := True;
  Result.MessageText := 'Zahlung per Gutschein erfolgreich.';
end;

end.






