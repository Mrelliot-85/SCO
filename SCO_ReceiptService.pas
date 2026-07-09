unit SCO_ReceiptService;

interface

uses
  System.SysUtils, System.JSON;

type
  TSCOReceiptService = class
  private
    function JsonResult(AOk: Boolean; const AMessage: string): string;
    function JsonTextResult(AOk: Boolean; const AMessage, AText: string): string;
    function TextValue(O: TJSONObject; const Name, Default: string): string;
    function FloatValue(O: TJSONObject; const Name: string; Default: Double): Double;
    function ReceiptTemplatePath: string;
    function LatestZVTJsonPath: string;
    function LatestZVTText: string;
    function BuildReceiptText(Root: TJSONObject; Items: TJSONArray): string;
    procedure EnsureDefaultTemplate;
    procedure PrintText(const Text: string);
  public
    function PreviewFromJson(const JsonText: string): string;
    function PrintFromJson(const JsonText: string): string;
    function TestPrint: string;
    function OpenDesigner: string;
    function PrintPlainText(const Text: string): string;
  end;

implementation

uses
  System.Classes, System.IOUtils, System.Types, Vcl.Printers, Winapi.ShellAPI,
  Winapi.Windows, Winapi.WinSpool, SCO_CONFIG, SCO_Logger;

function ReceiptWidth: Integer;
var
  MM: Integer;
begin
  MM := SCOConfig.BonBreiteMM;
  if MM <= 0 then MM := 80;
  if MM <= 58 then Exit(26);
  if MM >= 80 then Exit(42);
  Result := 28 + Round((MM - 58) * 14 / 22);
end;

function MmToPrinterX(MM: Double): Integer;
var
  DPI: Integer;
begin
  DPI := GetDeviceCaps(Printer.Canvas.Handle, LOGPIXELSX);
  if DPI <= 0 then
    DPI := 203;
  Result := Round(MM * DPI / 25.4);
end;

function MmToPrinterY(MM: Double): Integer;
var
  DPI: Integer;
begin
  DPI := GetDeviceCaps(Printer.Canvas.Handle, LOGPIXELSY);
  if DPI <= 0 then
    DPI := 203;
  Result := Round(MM * DPI / 25.4);
end;

function EscapeJson(const S: string): string;
begin
  Result := S;
  Result := StringReplace(Result, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
end;

function LineOf(const C: Char): string;
begin
  Result := StringOfChar(C, ReceiptWidth);
end;

function FitText(const S: string; Len: Integer): string;
begin
  Result := Trim(S);
  if Length(Result) > Len then
    Result := Copy(Result, 1, Len);
end;

function CenterText(const S: string): string;
var
  T: string;
  Pad: Integer;
begin
  T := FitText(S, ReceiptWidth);
  Pad := (ReceiptWidth - Length(T)) div 2;
  if Pad < 0 then
    Pad := 0;
  Result := StringOfChar(' ', Pad) + T;
end;

function TwoCol(const L, R: string): string;
var
  LeftText, RightText: string;
  Spaces: Integer;
begin
  RightText := FitText(R, 14);
  LeftText := FitText(L, ReceiptWidth - Length(RightText) - 1);
  Spaces := ReceiptWidth - Length(LeftText) - Length(RightText);
  if Spaces < 1 then
    Spaces := 1;
  Result := LeftText + StringOfChar(' ', Spaces) + RightText;
end;

function MoneyText(Value: Double): string;
begin
  Result := FormatFloat('0.00 EUR', Value);
end;

procedure AddWrapped(Lines: TStringList; const Text: string);
var
  Work, Part: string;
  P: Integer;
begin
  Work := Trim(StringReplace(Text, #13, '', [rfReplaceAll]));
  while Work <> '' do
  begin
    if Length(Work) <= ReceiptWidth then
    begin
      Lines.Add(Work);
      Break;
    end;

    P := ReceiptWidth;
    while (P > 1) and (Work[P] <> ' ') do
      Dec(P);
    if P <= 1 then
      P := ReceiptWidth;

    Part := Trim(Copy(Work, 1, P));
    if Part <> '' then
      Lines.Add(Part);
    Delete(Work, 1, P);
    Work := Trim(Work);
  end;
end;

procedure AddWrappedBlock(Lines: TStringList; const Text: string);
var
  Parts: TStringList;
  I: Integer;
begin
  Parts := TStringList.Create;
  try
    Parts.Text := Text;
    for I := 0 to Parts.Count - 1 do
    begin
      if Trim(Parts[I]) = '' then
        Lines.Add('')
      else
        AddWrapped(Lines, Parts[I]);
    end;
  finally
    Parts.Free;
  end;
end;
function TSCOReceiptService.JsonResult(AOk: Boolean; const AMessage: string): string;
begin
  if AOk then
    Result := '{"ok":true,"message":"' + EscapeJson(AMessage) + '"}'
  else
    Result := '{"ok":false,"message":"' + EscapeJson(AMessage) + '"}';
end;

function TSCOReceiptService.JsonTextResult(AOk: Boolean; const AMessage, AText: string): string;
begin
  if AOk then
    Result := '{"ok":true,"message":"' + EscapeJson(AMessage) + '","text":"' + EscapeJson(AText) + '"}'
  else
    Result := '{"ok":false,"message":"' + EscapeJson(AMessage) + '","text":"' + EscapeJson(AText) + '"}';
end;

function TSCOReceiptService.TextValue(O: TJSONObject; const Name, Default: string): string;
var
  V: TJSONValue;
begin
  Result := Default;
  if Assigned(O) then
  begin
    V := O.GetValue(Name);
    if Assigned(V) then
      Result := V.Value;
  end;
end;

function TSCOReceiptService.FloatValue(O: TJSONObject; const Name: string; Default: Double): Double;
var
  S: string;
begin
  S := StringReplace(TextValue(O, Name, ''), '.', ',', [rfReplaceAll]);
  Result := StrToFloatDef(S, Default);
end;

function TSCOReceiptService.ReceiptTemplatePath: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'reports\receipt.txt';
end;

function TSCOReceiptService.LatestZVTJsonPath: string;
var
  Files: TStringDynArray;
  F: string;
  BestDate, D: TDateTime;
begin
  Result := '';
  BestDate := 0;
  if not TDirectory.Exists(IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'ZVT') then
    Exit;

  Files := TDirectory.GetFiles(IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'ZVT', 'ZVT_Ergebnis_*.json');
  for F in Files do
  begin
    D := TFile.GetLastWriteTime(F);
    if (Result = '') or (D > BestDate) then
    begin
      Result := F;
      BestDate := D;
    end;
  end;
end;

function TSCOReceiptService.LatestZVTText: string;
var
  FileName: string;
  V: TJSONValue;
  O: TJSONObject;
  BetragCent: Integer;
  Betrag: Double;
begin
  Result := '';
  FileName := LatestZVTJsonPath;
  if (FileName = '') or (not FileExists(FileName)) then
    Exit;

  V := TJSONObject.ParseJSONValue(TFile.ReadAllText(FileName, TEncoding.UTF8));
  try
    if not (V is TJSONObject) then
      Exit;
    O := TJSONObject(V);
    BetragCent := StrToIntDef(TextValue(O, 'Betrag', '0'), 0);
    Betrag := BetragCent / 100;
    Result :=
      'EC-Zahlung' + sLineBreak +
      'Ergebnis: ' + TextValue(O, 'Ergebnistext', '') + sLineBreak +
      'Zeit: ' + TextValue(O, 'Zeit', '') + sLineBreak +
      'Karte: ' + TextValue(O, 'KartentypLang', '') + sLineBreak +
      'PAN: ' + TextValue(O, 'PAN', '') + sLineBreak +
      'Beleg: ' + TextValue(O, 'BelegNr', '') + sLineBreak +
      'AID: ' + TextValue(O, 'AID', '') + sLineBreak +
      'Betrag: ' + MoneyText(Betrag);
  finally
    V.Free;
  end;
end;

procedure TSCOReceiptService.EnsureDefaultTemplate;
var
  Lines: TStringList;
begin
  ForceDirectories(ExtractFilePath(ReceiptTemplatePath));
  if FileExists(ReceiptTemplatePath) then
    Exit;

  Lines := TStringList.Create;
  try
    Lines.Add('Vielen Dank fuer Ihren Einkauf!');
    Lines.Add('Ihr Herbst Hofladen Team');
    TFile.WriteAllText(ReceiptTemplatePath, Lines.Text, TEncoding.UTF8);
  finally
    Lines.Free;
  end;
end;

function TSCOReceiptService.BuildReceiptText(Root: TJSONObject; Items: TJSONArray): string;
var
  Lines, FooterLines: TStringList;
  I: Integer;
  Item: TJSONObject;
  Sum, GP, EP, Tax7, Tax19, Net7, Net19, ItemTax: Double;
  VatRate: Integer;
  Payment, PaymentText, ZVTText: string;
begin
  Lines := TStringList.Create;
  FooterLines := TStringList.Create;
  try
    Sum := 0;
    Tax7 := 0;
    Tax19 := 0;
    Net7 := 0;
    Net19 := 0;
    EnsureDefaultTemplate;

    Lines.Add(CenterText(TextValue(Root, 'shop', SCOConfig.Kunde)));
    if Trim(TextValue(Root, 'phone', '')) <> '' then
      Lines.Add(CenterText('Tel. ' + TextValue(Root, 'phone', '')));
    if Trim(TextValue(Root, 'bonNo', '')) <> '' then
      Lines.Add(CenterText('Bon Nr. ' + TextValue(Root, 'bonNo', '')));
    Lines.Add(CenterText(FormatDateTime('dd.mm.yyyy hh:nn:ss', Now)));
    Lines.Add(LineOf('='));

    for I := 0 to Items.Count - 1 do
    begin
      if not (Items.Items[I] is TJSONObject) then
        Continue;
      Item := TJSONObject(Items.Items[I]);
      GP := FloatValue(Item, 'gp', 0);
      EP := FloatValue(Item, 'ep', 0);
      Sum := Sum + GP;
      VatRate := Round(FloatValue(Item, 'vatRate', FloatValue(Item, 'mwst', 7)));
      if VatRate <> 19 then
        VatRate := 7;
      ItemTax := GP - (GP / (1 + (VatRate / 100)));
      if VatRate = 19 then
      begin
        Tax19 := Tax19 + ItemTax;
        Net19 := Net19 + (GP - ItemTax);
      end
      else
      begin
        Tax7 := Tax7 + ItemTax;
        Net7 := Net7 + (GP - ItemTax);
      end;

      Lines.Add(FitText(TextValue(Item, 'name', 'Artikel'), ReceiptWidth));
      Lines.Add(TwoCol(
        TextValue(Item, 'qtyText', TextValue(Item, 'qty', '1')) + ' ' + TextValue(Item, 'unit', '') +
        ' x ' + FormatFloat('0.00', EP), MoneyText(GP)));
    end;

    Lines.Add(LineOf('-'));
    if (Net7 <> 0) or (Tax7 <> 0) then
    begin
      Lines.Add(TwoCol('Netto 7%', MoneyText(Net7)));
      Lines.Add(TwoCol('MwSt 7%', MoneyText(Tax7)));
    end;
    if (Net19 <> 0) or (Tax19 <> 0) then
    begin
      Lines.Add(TwoCol('Netto 19%', MoneyText(Net19)));
      Lines.Add(TwoCol('MwSt 19%', MoneyText(Tax19)));
    end;
    Lines.Add(TwoCol('SUMME', MoneyText(Sum)));
    Lines.Add(LineOf('='));

    Payment := TextValue(Root, 'payment', '');
    if SameText(Payment, 'Karte') or SameText(Payment, 'EC') or SameText(Payment, 'ZVT') then
    begin
      PaymentText := 'Zahlart: EC-/Kartenzahlung';
      ZVTText := LatestZVTText;
    end
    else if SameText(Payment, 'Bargeld') or SameText(Payment, 'BAR') then
    begin
      PaymentText := 'Zahlart: Barzahlung am Zahlautomaten';
      ZVTText := '';
    end
    else
    begin
      PaymentText := 'Zahlart: ' + Payment;
      ZVTText := '';
    end;

    Lines.Add(PaymentText);
    if Trim(ZVTText) <> '' then
    begin
      Lines.Add(LineOf('-'));
      AddWrappedBlock(Lines, ZVTText);
    end;
    Lines.Add(LineOf('-'));
    if SCOConfig.TSEAktiv then
    begin
      Lines.Add('TSE: aktiv');
      Lines.Add('Anbieter: ' + SCOConfig.TSEProvider);
      if Trim(SCOConfig.TSESerial) <> '' then
        AddWrapped(Lines, 'Seriennummer: ' + SCOConfig.TSESerial);
      Lines.Add('TSE-Signatur: Schnittstelle vorbereitet');
    end
    else
    begin
      AddWrappedBlock(Lines, SCOConfig.TSEInactiveText);
    end;
    if Trim(SCOConfig.UStId) <> '' then
      AddWrapped(Lines, 'USt-IdNr.: ' + SCOConfig.UStId);
    Lines.Add(LineOf('-'));

    if FileExists(ReceiptTemplatePath) then
    begin
      FooterLines.LoadFromFile(ReceiptTemplatePath, TEncoding.UTF8);
      for I := 0 to FooterLines.Count - 1 do
        if Trim(FooterLines[I]) <> '' then
          Lines.Add(CenterText(FooterLines[I]));
    end;

    Lines.Add('');
    Lines.Add('');
    Lines.Add('');
    Result := Lines.Text;
  finally
    FooterLines.Free;
    Lines.Free;
  end;
end;

procedure TSCOReceiptService.PrintText(const Text: string);
var
  Lines: TStringList;
  I, Y, X, LineHeight, Bottom: Integer;
  PrinterName, Available: string;
  Needed: DWORD;
  Found: Boolean;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := Text;

    SCOConfig.Load;
    PrinterName := Trim(SCOConfig.BonDrucker);
    if PrinterName = '' then
    begin
      Needed := 0;
      GetDefaultPrinter(nil, @Needed);
      if Needed = 0 then
        raise Exception.Create('In Windows ist kein Standarddrucker eingerichtet.');
      SetLength(PrinterName, Needed);
      if not GetDefaultPrinter(PChar(PrinterName), @Needed) then
        RaiseLastOSError;
      SetLength(PrinterName, StrLen(PChar(PrinterName)));
    end;

    Found := False;
    Available := '';
    for I := 0 to Printer.Printers.Count - 1 do
    begin
      if Available <> '' then Available := Available + '; ';
      Available := Available + Printer.Printers[I];
      if SameText(Trim(Printer.Printers[I]), Trim(PrinterName)) then
      begin
        Printer.PrinterIndex := I;
        Found := True;
      end;
    end;
    if not Found then
      raise Exception.Create('Bondrucker nicht gefunden: ' + PrinterName + '. Verfuegbar: ' + Available);

    LogTransaction('RECEIPT PRINTER SELECTED=' + PrinterName + ' INDEX=' + IntToStr(Printer.PrinterIndex));
    Printer.Title := 'FOODWARE SCO Bon';
    Printer.BeginDoc;
    try
      Printer.Canvas.Font.Name := 'Consolas';
      if SCOConfig.BonBreiteMM <= 58 then
        Printer.Canvas.Font.Size := 6
      else
        Printer.Canvas.Font.Size := 8;
      X := MmToPrinterX(SCOConfig.BonRandLinksMM);
      Y := MmToPrinterY(3.0);
      LineHeight := Printer.Canvas.TextHeight('Hg') + MmToPrinterY(0.6);
      Bottom := Printer.PageHeight - LineHeight - MmToPrinterY(3.0);

      for I := 0 to Lines.Count - 1 do
      begin
        if Y > Bottom then
        begin
          Printer.NewPage;
          Y := MmToPrinterY(3.0);
        end;
        Printer.Canvas.TextOut(X, Y, Lines[I]);
        Inc(Y, LineHeight);
      end;
    finally
      Printer.EndDoc;
    end;
  finally
    Lines.Free;
  end;
end;
function TSCOReceiptService.TestPrint: string;
var
  TestText: string;
begin
  try
    TestText := CenterText('FOODWARE SCO') + sLineBreak +
      CenterText('Bondrucker Test') + sLineBreak +
      LineOf('=') + sLineBreak +
      'Datum: ' + FormatDateTime('dd.mm.yyyy hh:nn:ss', Now) + sLineBreak +
      'Der Bondruck funktioniert.' + sLineBreak +
      LineOf('-') + sLineBreak + sLineBreak + sLineBreak;
    TThread.Synchronize(nil,
      procedure
      begin
        PrintText(TestText);
      end);
    Result := JsonResult(True, 'Testbon wurde an den Windows-Drucker uebergeben.');
  except
    on E: Exception do
    begin
      LogError('RECEIPT TEST ERROR ' + E.ClassName + ': ' + E.Message);
      Result := JsonResult(False, 'Bondrucker-Test fehlgeschlagen: ' + E.Message);
    end;
  end;
end;

function TSCOReceiptService.PrintFromJson(const JsonText: string): string;
var
  Root: TJSONObject;
  Items: TJSONArray;
  V: TJSONValue;
  ReceiptText: string;
begin
  Result := JsonResult(False, 'Bon konnte nicht gedruckt werden.');
  V := TJSONObject.ParseJSONValue(JsonText);
  try
    if not (V is TJSONObject) then
      Exit(JsonResult(False, 'Ungueltige Bondaten.'));

    Root := TJSONObject(V);
    Items := Root.GetValue<TJSONArray>('items');
    if not Assigned(Items) or (Items.Count = 0) then
      Exit(JsonResult(False, 'Keine Artikel fuer den Bondruck vorhanden.'));

    ReceiptText := BuildReceiptText(Root, Items);
    TThread.Synchronize(nil,
      procedure
      begin
        PrintText(ReceiptText);
      end);

    LogTransaction('RECEIPT DIRECT PRINT OK items=' + IntToStr(Items.Count));
    Result := JsonResult(True, 'Bon wurde direkt gedruckt.');
  except
    on E: Exception do
    begin
      LogError('RECEIPT DIRECT PRINT ERROR ' + E.ClassName + ': ' + E.Message);
      Result := JsonResult(False, 'Bondruck Fehler: ' + E.Message);
    end;
  end;
  V.Free;
end;

function TSCOReceiptService.PreviewFromJson(const JsonText: string): string;
var
  Root: TJSONObject;
  Items: TJSONArray;
  V: TJSONValue;
  ReceiptText: string;
begin
  Result := JsonTextResult(False, 'Bonvorschau konnte nicht erstellt werden.', '');
  V := TJSONObject.ParseJSONValue(JsonText);
  try
    if not (V is TJSONObject) then
      Exit(JsonTextResult(False, 'Ungueltige Bondaten.', ''));

    Root := TJSONObject(V);
    Items := Root.GetValue<TJSONArray>('items');
    if not Assigned(Items) or (Items.Count = 0) then
      Exit(JsonTextResult(False, 'Keine Artikel fuer die Bonvorschau vorhanden.', ''));

    ReceiptText := BuildReceiptText(Root, Items);
    Result := JsonTextResult(True, 'Bonvorschau erstellt.', ReceiptText);
  except
    on E: Exception do
    begin
      LogError('RECEIPT PREVIEW ERROR ' + E.ClassName + ': ' + E.Message);
      Result := JsonTextResult(False, 'Bonvorschau Fehler: ' + E.Message, '');
    end;
  end;
  V.Free;
end;
function TSCOReceiptService.PrintPlainText(const Text: string): string;
begin
  try
    TThread.Synchronize(nil,
      procedure
      begin
        PrintText(Text);
      end);
    Result := JsonResult(True, 'Text wurde an den Bondrucker uebergeben.');
  except
    on E: Exception do
    begin
      LogError('RECEIPT PLAIN PRINT ERROR ' + E.ClassName + ': ' + E.Message);
      Result := JsonResult(False, 'Bondruck Fehler: ' + E.Message);
    end;
  end;
end;
function TSCOReceiptService.OpenDesigner: string;
var
  Code: HINST;
begin
  try
    EnsureDefaultTemplate;
    Code := ShellExecute(0, 'open', PChar('notepad.exe'), PChar(ReceiptTemplatePath),
      PChar(ExtractFilePath(ReceiptTemplatePath)), SW_SHOWNORMAL);
    if Code > 32 then
      Result := JsonResult(True, 'Bon-Textvorlage geoeffnet: ' + ReceiptTemplatePath)
    else
      Result := JsonResult(False, 'Bon-Textvorlage konnte nicht geoeffnet werden. Code ' + IntToStr(Code));
  except
    on E: Exception do
    begin
      LogError('RECEIPT TEMPLATE ERROR ' + E.ClassName + ': ' + E.Message);
      Result := JsonResult(False, 'Vorlagen Fehler: ' + E.Message);
    end;
  end;
end;

end.









