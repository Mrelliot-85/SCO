unit SCO_CONFIG;
interface
uses
  System.SysUtils, System.Classes, System.IniFiles;
type
  TSCOConfig = class
  private
    FIniPath: string;
  public
    KundenNr: Integer;
    NLKey: Integer;
    DemoModus: Boolean;
    DemoBonjournalSchreiben: Boolean;
    DemoWebUISchreiben: Boolean;
    ManuelleArtikel: Boolean;
    Kunde: string;
    Subtitle: string;
    Telefon: string;
    Adresse: string;
    Logo: string;
    FarbeHaupt: string;
    FarbeDunkel: string;
    FarbeAkzent: string;
    Port: Integer;
    PaymentBar: Boolean;
    PaymentEC: Boolean;
    PaymentKundenkarte: Boolean;
    PaymentGutschein: Boolean;
    BonAutoDruck: Boolean;
    BonDrucker: string;
    BonBreiteMM: Integer;
    BonRandLinksMM: Double;
    TSEAktiv: Boolean;
    TSEProvider: string;
    TSEDevicePath: string;
    TSEApiUrl: string;
    TSEClientId: string;
    TSESerial: string;
    TSEInactiveText: string;
    UStId: string;
    BewertungAktiv: Boolean;
    ZVT_Host: string;
    ZVT_ExePath: string;
    ZVT_Kasse: Integer;
    ZVT_Port: Integer;
    ZVT_Lizenz: string;
    ZVT_Test: Boolean;
    ZVT_Dialog: Integer;
    ZVT_Kassedruck: Integer;
    Beschreibung: string;
    CheckEANMod10: Boolean;
    EANRules: string;
    LabelingTagLength: Integer;
    EANLabelWriteTagInfo: Boolean;
    LabelDrucker: string;
    LabelDruckerHost: string;
    LabelDruckerPort: Integer;
    RFIDAktiv: Boolean;
    RFIDTagLength: Integer;
    RFIDTCPPort: Integer;
    RFIDHost: string;
    RFIDBindIP: string;
    RFIDExitAlarmActive: Boolean;
    RFIDExitAlarmAntenna: Integer;
    RFIDExitAlarmSeconds: Integer;
    RFIDExitAlarmSystemBeep: Boolean;
    RFIDExitAlarmSound: string;
    RFIDStartOnScan: Boolean;
    ScaleActive: Boolean;
    ScaleVendor: string;
    ScaleMode: string;
    ScaleComPort: string;
    ScaleBaud: Integer;
    ScaleHost: string;
    ScaleTCPPort: Integer;
    ScaleRequest: string;
    ScaleTimeoutMS: Integer;


  EnableEANLabel  : Boolean;
  EnableRFIDLabel : Boolean;
  EnableRFIDEncode: Boolean;

  LabelingStartMode : string;

    BewertungFrage1: string;
    BewertungFrage2: string;
    BewertungFrage3: string;
    BewertungFrage4: string;
    CashLogyConnectorExe: string;
    CashLogyConnectorHost: string;
    CashLogyConnectorPort: Integer;
    DailyCloseActive: Boolean;
    DailyCloseTime: string;
    DailyCloseZVT: Boolean;
    DailyCloseCashLogy: Boolean;
    BonjournalFilialId: string;
    WebUIAktiv: Boolean;
    WebUIHost: string;
    WebUIPort: Integer;
    WebUIDatabase: string;
    WebUIUser: string;
    WebUIPassword: string;
    ESLActive: Boolean;
    ESLHost: string;
    ESLPort: Integer;
    ESLLocation: string;
    ESLArticleTemplate: string;
    ESLOfferTemplate: string;
    ESLTimeoutMS: Integer;

    DBFirebird: string;
    DBHost: string;
    DBPort: Integer;
    DBUser: string;
    DBPassword: string;
    DBCharset: string;
    constructor Create;
    procedure Load;
    procedure SaveFromJson(const JsonText: string);
    function AsJson: string;
  end;
var
  SCOConfig: TSCOConfig;
implementation
uses
  System.JSON;
constructor TSCOConfig.Create;
begin
  inherited Create;
  FIniPath := ExtractFilePath(ParamStr(0)) + 'config.ini';
end;
function BoolJson(Value: Boolean): string;
begin
  if Value then Result := 'true' else Result := 'false';
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
function JsonStr(O: TJSONObject; const Name, Default: string): string;
var V: TJSONValue;
begin
  Result := Default;
  if Assigned(O) then
  begin
    V := O.GetValue(Name);
    if Assigned(V) then Result := V.Value;
  end;
end;
function DecodeIniText(const S: string): string;
begin
  Result := StringReplace(S, '\n', sLineBreak, [rfReplaceAll]);
end;

function EncodeIniText(const S: string): string;
begin
  Result := StringReplace(S, #13#10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
end;

function JsonFloat(O: TJSONObject; const Name: string; Default: Double): Double;
var
  V: TJSONValue;
  FS: TFormatSettings;
  Text: string;
begin
  Result := Default;
  if Assigned(O) then
  begin
    V := O.GetValue(Name);
    if Assigned(V) then
    begin
      if V is TJSONNumber then
        Result := TJSONNumber(V).AsDouble
      else
      begin
        FS := TFormatSettings.Create;
        FS.DecimalSeparator := '.';
        Text := StringReplace(V.Value, ',', '.', [rfReplaceAll]);
        if not TryStrToFloat(Text, Result, FS) then
          Result := Default;
      end;
    end;
  end;
end;
function JsonBool(O: TJSONObject; const Name: string; Default: Boolean): Boolean;
var V: TJSONValue;
begin
  Result := Default;
  if Assigned(O) then
  begin
    V := O.GetValue(Name);
    if Assigned(V) then
      Result := SameText(V.Value, 'true') or (V.Value = '1');
  end;
end;
procedure TSCOConfig.Load;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(FIniPath);
  try
    Kunde       := Ini.ReadString('Design', 'Kunde', 'Metzgerei Burgard');
    Subtitle    := Ini.ReadString('Design', 'Subtitle', 'Self-Checkout');
    Telefon     := Ini.ReadString('Design', 'Telefon', '');
    Adresse     := DecodeIniText(Ini.ReadString('Design', 'Adresse', ''));
    Logo        := Ini.ReadString('Design', 'Logo', '');
    KundenNr    := Ini.ReadInteger('Einstellung', 'Kunde', 0);
    NLKey       := Ini.ReadInteger('Einstellung', 'NL_KEY', 10);
    DemoModus   := Ini.ReadInteger('Einstellung', 'Demomodus', 0) = 1;
    DemoBonjournalSchreiben := Ini.ReadInteger('Demo', 'BonjournalSchreiben', 1) = 1;
    DemoWebUISchreiben := Ini.ReadInteger('Demo', 'WebUISchreiben', 0) = 1;
    ManuelleArtikel := Ini.ReadInteger('SCO', 'ManuelleArtikel', 1) = 1;
    FarbeHaupt  := Ini.ReadString('Design', 'Farbe_Haupt', '#107a2a');
    FarbeDunkel := Ini.ReadString('Design', 'Farbe_Dunkel', '#101c29');
    FarbeAkzent := Ini.ReadString('Design', 'Farbe_Akzent', '#f2b01e');
    Port        := Ini.ReadInteger('Server', 'Port', 8090);
    DBFirebird  := Ini.ReadString('Datenbank', 'Firebird', '');
    DBHost := Trim(Ini.ReadString('Datenbank', 'Host', 'localhost'));
    DBPort := Ini.ReadInteger('Datenbank', 'Port', 3050);
    DBUser := Ini.ReadString('Datenbank', 'User', 'SYSDBA');
    DBPassword := Ini.ReadString('Datenbank', 'Password', 'masterkey');
    DBCharset := Ini.ReadString('Datenbank', 'Charset', 'NONE');
    PaymentBar         := Ini.ReadInteger('Zahlung', 'Bar', 1) = 1;
    PaymentEC          := Ini.ReadInteger('Zahlung', 'EC', 1) = 1;
    PaymentKundenkarte := Ini.ReadInteger('Zahlung', 'Kundenkarte', 1) = 1;
    PaymentGutschein   := Ini.ReadInteger('Zahlung', 'Gutschein', 1) = 1;
    Beschreibung := Ini.ReadString('Design', 'Beschreibung', '');

    BewertungFrage1 := Ini.ReadString('Bewertung', 'Frage1', '');
    BewertungFrage2 := Ini.ReadString('Bewertung', 'Frage2', '');
    BewertungFrage3 := Ini.ReadString('Bewertung', 'Frage3', '');
    BewertungFrage4 := Ini.ReadString('Bewertung', 'Frage4', '');
    BonAutoDruck    := Ini.ReadInteger('Bon', 'AutoDruck', 0) = 1;
    BonDrucker      := Ini.ReadString('Bon', 'Drucker', '');
    BonBreiteMM     := Ini.ReadInteger('Bon', 'BreiteMM', 80);
    BonRandLinksMM  := Ini.ReadFloat('Bon', 'RandLinksMM', 0);
    if BonRandLinksMM <= 0 then
      if BonBreiteMM <= 58 then BonRandLinksMM := 8 else BonRandLinksMM := 3;
    TSEAktiv       := Ini.ReadInteger('TSE', 'Aktiv', 0) = 1;
    TSEProvider    := Ini.ReadString('TSE', 'Provider', 'Swissbit');
    TSEDevicePath  := Ini.ReadString('TSE', 'DevicePath', '');
    TSEApiUrl      := Ini.ReadString('TSE', 'ApiUrl', '');
    TSEClientId    := Ini.ReadString('TSE', 'ClientId', 'FOODWARE_SCO');
    TSESerial      := Ini.ReadString('TSE', 'Serial', '');
    TSEInactiveText := DecodeIniText(Ini.ReadString('TSE', 'InactiveText', 'Hinweis:\nDieses Kassensystem verarbeitet ausschliesslich unbare Zahlungen (EC-/Kreditkarte mit PIN) gemaess Paragraph 146a AO. Eine Technische Sicherheitseinrichtung (TSE) ist daher nicht erforderlich.'));
    UStId          := Ini.ReadString('TSE', 'UStId', '');
    BewertungAktiv  := Ini.ReadInteger('Bewertung', 'Aktiv', 1) = 1;
    ZVT_Host   := Ini.ReadString('ZVT', 'Host', '');
    ZVT_ExePath := Ini.ReadString('ZVT', 'Exe', Ini.ReadString('ZVT', 'EasyZVT', ''));
    ZVT_Kasse  := Ini.ReadInteger('ZVT', 'Kasse', 1);
    ZVT_Port   := Ini.ReadInteger('ZVT', 'Port', 5577);
    ZVT_Lizenz := Ini.ReadString('ZVT', 'Lizenz', '');
    ZVT_Test   := Ini.ReadInteger('ZVT', 'Test', 0) = 1;
    ZVT_Dialog := Ini.ReadInteger('ZVT', 'Dialog', Ini.ReadInteger('ZVT', 'dialog', 0));
    ZVT_Kassedruck := Ini.ReadInteger('ZVT', 'Kassedruck', Ini.ReadInteger('ZVT', 'kassedruck', 0));
    CashLogyConnectorExe :=   Ini.ReadString('Cashlogy', 'CashLogyConnectorExe', '');
    CashLogyConnectorHost :=  Ini.ReadString('Cashlogy', 'CashLogyConnectorHost', '127.0.0.1');
    CashLogyConnectorPort :=  Ini.ReadInteger('Cashlogy', 'CashLogyConnectorPort', 8092);
    DailyCloseActive := Ini.ReadInteger('Kassenabschluss', 'Aktiv', 0) = 1;
    DailyCloseTime := Ini.ReadString('Kassenabschluss', 'Uhrzeit', '02:00');
    DailyCloseZVT := Ini.ReadInteger('Kassenabschluss', 'ZVT', 1) = 1;
    DailyCloseCashLogy := Ini.ReadInteger('Kassenabschluss', 'CashLogy', 1) = 1;
    BonjournalFilialId := Ini.ReadString('Bonjournal', 'Filial_ID', IntToStr(KundenNr));
    WebUIAktiv := Ini.ReadInteger('WebUI', 'Aktiv', 0) = 1;
    WebUIHost := Ini.ReadString('WebUI', 'Host', '');
    WebUIPort := Ini.ReadInteger('WebUI', 'Port', 3306);
    WebUIDatabase := Ini.ReadString('WebUI', 'Database', '');
    WebUIUser := Ini.ReadString('WebUI', 'User', '');
    WebUIPassword := Ini.ReadString('WebUI', 'Password', '');
    ESLActive := Ini.ReadInteger('ESL', 'Aktiv', 0) = 1;
    ESLHost := Ini.ReadString('ESL', 'Host', '127.0.0.1');
    ESLPort := Ini.ReadInteger('ESL', 'Port', 49190);
    ESLLocation := Ini.ReadString('ESL', 'Location', '1');
    ESLArticleTemplate := Ini.ReadString('ESL', 'ArticleTemplate', 'article-266');
    ESLOfferTemplate := Ini.ReadString('ESL', 'OfferTemplate', 'offer-42');
    ESLTimeoutMS := Ini.ReadInteger('ESL', 'TimeoutMS', 8000);

    CheckEANMod10 :=      Ini.ReadBool('Labeling', 'CheckEANMod10', True);
    EANRules := Trim(Ini.ReadString('EAN', 'Regeln', '')); 
    LabelingTagLength :=  Ini.ReadInteger('Labeling', 'TagLength', 24);
    EANLabelWriteTagInfo := Ini.ReadBool('Labeling', 'EAN_TagInfo', False);
    LabelDrucker := Ini.ReadString('Labeling', 'Drucker', '');
    LabelDruckerHost := Trim(Ini.ReadString('Labeling', 'DruckerHost', ''));
    LabelDruckerPort := Ini.ReadInteger('Labeling', 'DruckerPort', 9100);
    RFIDAktiv := Ini.ReadInteger('RFID', 'Aktiv', 0) = 1;
    RFIDTagLength := Ini.ReadInteger('RFID', 'TagLength', LabelingTagLength);
    RFIDTCPPort := Ini.ReadInteger('RFID', 'TCPPort', 3178);
    RFIDHost := Ini.ReadString('RFID', 'Host', '');
    RFIDBindIP := Ini.ReadString('RFID', 'BindIP', '0.0.0.0');
    RFIDExitAlarmActive := Ini.ReadInteger('RFID', 'Ausgangskontrolle', 1) = 1;
    RFIDExitAlarmAntenna := Ini.ReadInteger('RFID', 'AusgangsAntenne', 4);
    RFIDExitAlarmSeconds := Ini.ReadInteger('RFID', 'AlarmSekunden', 20);
    RFIDExitAlarmSystemBeep := Ini.ReadInteger('RFID', 'AlarmSystemBeep', 1) = 1;
    RFIDExitAlarmSound := Ini.ReadString('RFID', 'AlarmSound', '');
    RFIDStartOnScan := Ini.ReadInteger('RFID', 'StartBeiErfassung', 0) = 1;
    ScaleActive := Ini.ReadInteger('Waage', 'Aktiv', 0) = 1;
    ScaleVendor := Ini.ReadString('Waage', 'Hersteller', 'soehnle3820');
    ScaleMode := LowerCase(Ini.ReadString('Waage', 'Modus', 'serial'));
    ScaleComPort := Ini.ReadString('Waage', 'COM', 'COM3');
    ScaleBaud := Ini.ReadInteger('Waage', 'Baud', 9600);
    ScaleHost := Ini.ReadString('Waage', 'Host', '');
    ScaleTCPPort := Ini.ReadInteger('Waage', 'Port', 23);
    ScaleRequest := Ini.ReadString('Waage', 'Request', '<A>');
    ScaleTimeoutMS := Ini.ReadInteger('Waage', 'TimeoutMS', 2500);

    EnableEANLabel :=      Ini.ReadBool('Labeling', 'EAN_label', True);

    EnableRFIDLabel :=       Ini.ReadBool('Labeling', 'RFID_label', True);

    EnableRFIDEncode :=       Ini.ReadBool('Labeling', 'RFID_encode', True);

    LabelingStartMode :=   UpperCase(Trim(Ini.ReadString('Labeling','start','EAN_LABEL')));


 finally
 Ini.Free;
  end;
end;
procedure TSCOConfig.SaveFromJson(const JsonText: string);
var
  Root, Theme, Payment, Receipt, Rating, ZVT, CashLogy, DailyClose, Database, TSE, Journal, WebUI, RFID, Scale, Labeling, ESL: TJSONObject;
  V: TJSONValue;
  Ini: TIniFile;
begin
  V := TJSONObject.ParseJSONValue(JsonText);
  try
    if not (V is TJSONObject) then
      raise Exception.Create('Ungueltige JSON-Daten');
    Root := TJSONObject(V);
    Theme := Root.GetValue<TJSONObject>('theme');
    Payment := Root.GetValue<TJSONObject>('payment');
    Receipt := Root.GetValue<TJSONObject>('receipt');
    Rating := Root.GetValue<TJSONObject>('rating');
    ZVT := Root.GetValue<TJSONObject>('zvt');
    CashLogy := Root.GetValue<TJSONObject>('cashlogy');
    DailyClose := Root.GetValue<TJSONObject>('dailyClose');
    Database := Root.GetValue<TJSONObject>('database');
    TSE := Root.GetValue<TJSONObject>('tse');
    Journal := Root.GetValue<TJSONObject>('journal');
    WebUI := Root.GetValue<TJSONObject>('webui');
    RFID := Root.GetValue<TJSONObject>('rfid');
    Scale := Root.GetValue<TJSONObject>('scale');
    Labeling := Root.GetValue<TJSONObject>('labeling');
    ESL := Root.GetValue<TJSONObject>('esl');
    Ini := TIniFile.Create(FIniPath);
    try
      Ini.WriteString('Design', 'Kunde', JsonStr(Root, 'customer', Kunde));
      Ini.WriteString('Design', 'Subtitle', JsonStr(Root, 'subtitle', Subtitle));
      Ini.WriteString('Design', 'Telefon', JsonStr(Root, 'phone', Telefon));
      Ini.WriteString('Design', 'Adresse', EncodeIniText(JsonStr(Root, 'address', Adresse)));
      Ini.WriteString('Design', 'Logo', JsonStr(Root, 'logo', Logo));
      Ini.WriteString('Design', 'Farbe_Haupt', JsonStr(Theme, 'green', FarbeHaupt));
      Ini.WriteString('Design', 'Farbe_Dunkel', JsonStr(Theme, 'dark', FarbeDunkel));
      Ini.WriteString('Design', 'Farbe_Akzent', JsonStr(Theme, 'accent', FarbeAkzent));
      Ini.WriteInteger('Einstellung', 'Demomodus', Ord(JsonBool(Root, 'demoMode', DemoModus)));
      Ini.WriteInteger('Demo', 'BonjournalSchreiben', Ord(JsonBool(Root, 'demoWriteJournal', DemoBonjournalSchreiben)));
      Ini.WriteInteger('Demo', 'WebUISchreiben', Ord(JsonBool(Root, 'demoWriteWebUI', DemoWebUISchreiben)));
      Ini.WriteInteger('SCO', 'ManuelleArtikel', Ord(JsonBool(Root, 'manualProducts', ManuelleArtikel)));
      Ini.WriteInteger('Zahlung', 'Bar', Ord(JsonBool(Payment, 'cash', PaymentBar)));
      Ini.WriteInteger('Zahlung', 'EC', Ord(JsonBool(Payment, 'ec', PaymentEC)));
      Ini.WriteInteger('Zahlung', 'Kundenkarte', Ord(JsonBool(Payment, 'customer', PaymentKundenkarte)));
      Ini.WriteInteger('Zahlung', 'Gutschein', Ord(JsonBool(Payment, 'coupon', PaymentGutschein)));
      Ini.WriteInteger('Bon', 'AutoDruck', Ord(JsonBool(Receipt, 'autoPrint', BonAutoDruck)));
      Ini.WriteString('Bon', 'Drucker', JsonStr(Receipt, 'printer', BonDrucker));
      Ini.WriteInteger('Bon', 'BreiteMM', StrToIntDef(JsonStr(Receipt, 'widthMm', IntToStr(BonBreiteMM)), BonBreiteMM));
      Ini.WriteFloat('Bon', 'RandLinksMM', JsonFloat(Receipt, 'leftMarginMm', BonRandLinksMM));
      Ini.WriteString('EAN', 'Regeln', JsonStr(Root, 'eanRules', EANRules));
      Ini.WriteInteger('TSE', 'Aktiv', Ord(JsonBool(TSE, 'active', TSEAktiv)));
      Ini.WriteString('TSE', 'Provider', JsonStr(TSE, 'provider', TSEProvider));
      Ini.WriteString('TSE', 'DevicePath', JsonStr(TSE, 'devicePath', TSEDevicePath));
      Ini.WriteString('TSE', 'ApiUrl', JsonStr(TSE, 'apiUrl', TSEApiUrl));
      Ini.WriteString('TSE', 'ClientId', JsonStr(TSE, 'clientId', TSEClientId));
      Ini.WriteString('TSE', 'Serial', JsonStr(TSE, 'serial', TSESerial));
      Ini.WriteString('TSE', 'InactiveText', EncodeIniText(JsonStr(TSE, 'inactiveText', TSEInactiveText)));
      Ini.WriteString('TSE', 'UStId', JsonStr(TSE, 'ustId', UStId));
      Ini.WriteInteger('Bewertung', 'Aktiv', Ord(JsonBool(Rating, 'active', BewertungAktiv)));
      if Rating <> nil then
      begin
        if (Rating.GetValue('questions') is TJSONArray) and (TJSONArray(Rating.GetValue('questions')).Count > 0) then
        begin
          Ini.WriteString('Bewertung', 'Frage1', TJSONArray(Rating.GetValue('questions')).Items[0].Value);
          if TJSONArray(Rating.GetValue('questions')).Count > 1 then
            Ini.WriteString('Bewertung', 'Frage2', TJSONArray(Rating.GetValue('questions')).Items[1].Value);
          if TJSONArray(Rating.GetValue('questions')).Count > 2 then
            Ini.WriteString('Bewertung', 'Frage3', TJSONArray(Rating.GetValue('questions')).Items[2].Value);
          if TJSONArray(Rating.GetValue('questions')).Count > 3 then
            Ini.WriteString('Bewertung', 'Frage4', TJSONArray(Rating.GetValue('questions')).Items[3].Value);
        end;
      end;
      Ini.WriteString('ZVT', 'Host', JsonStr(ZVT, 'host', ZVT_Host));
      Ini.WriteString('ZVT', 'Exe', JsonStr(ZVT, 'exe', ZVT_ExePath));
      Ini.WriteInteger('ZVT', 'Kasse', StrToIntDef(JsonStr(ZVT, 'kasse', IntToStr(ZVT_Kasse)), ZVT_Kasse));
      Ini.WriteInteger('ZVT', 'Port', StrToIntDef(JsonStr(ZVT, 'port', IntToStr(ZVT_Port)), ZVT_Port));
      Ini.WriteString('ZVT', 'Lizenz', JsonStr(ZVT, 'lizenz', ZVT_Lizenz));
      Ini.WriteInteger('ZVT', 'Test', Ord(JsonBool(ZVT, 'test', ZVT_Test)));
      Ini.WriteInteger('ZVT', 'Dialog', StrToIntDef(JsonStr(ZVT, 'dialog', IntToStr(ZVT_Dialog)), ZVT_Dialog));
      Ini.WriteInteger('ZVT', 'Kassedruck', StrToIntDef(JsonStr(ZVT, 'kassedruck', IntToStr(ZVT_Kassedruck)), ZVT_Kassedruck));
      Ini.WriteString('Cashlogy', 'CashLogyConnectorExe', JsonStr(CashLogy, 'exe', CashLogyConnectorExe));
      Ini.WriteString('Cashlogy', 'CashLogyConnectorHost', JsonStr(CashLogy, 'host', CashLogyConnectorHost));
      Ini.WriteInteger('Cashlogy', 'CashLogyConnectorPort', StrToIntDef(JsonStr(CashLogy, 'port', IntToStr(CashLogyConnectorPort)), CashLogyConnectorPort));
      Ini.WriteInteger('Kassenabschluss', 'Aktiv', Ord(JsonBool(DailyClose, 'active', DailyCloseActive)));
      Ini.WriteString('Kassenabschluss', 'Uhrzeit', JsonStr(DailyClose, 'time', DailyCloseTime));
      Ini.WriteInteger('Kassenabschluss', 'ZVT', Ord(JsonBool(DailyClose, 'zvt', DailyCloseZVT)));
      Ini.WriteInteger('Kassenabschluss', 'CashLogy', Ord(JsonBool(DailyClose, 'cashlogy', DailyCloseCashLogy)));
      Ini.WriteString('Datenbank', 'Firebird', JsonStr(Database, 'database', DBFirebird));
      Ini.WriteString('Datenbank', 'Host', JsonStr(Database, 'host', DBHost));
      Ini.WriteInteger('Datenbank', 'Port', StrToIntDef(JsonStr(Database, 'port', IntToStr(DBPort)), DBPort));
      Ini.WriteString('Datenbank', 'User', JsonStr(Database, 'user', DBUser));
      Ini.WriteString('Datenbank', 'Password', JsonStr(Database, 'password', DBPassword));
      Ini.WriteString('Datenbank', 'Charset', JsonStr(Database, 'charset', DBCharset));
      Ini.WriteString('Bonjournal', 'Filial_ID', JsonStr(Journal, 'filialId', BonjournalFilialId));
      Ini.WriteInteger('WebUI', 'Aktiv', Ord(JsonBool(WebUI, 'active', WebUIAktiv)));
      Ini.WriteString('WebUI', 'Host', JsonStr(WebUI, 'host', WebUIHost));
      Ini.WriteInteger('WebUI', 'Port', StrToIntDef(JsonStr(WebUI, 'port', IntToStr(WebUIPort)), WebUIPort));
      Ini.WriteString('WebUI', 'Database', JsonStr(WebUI, 'database', WebUIDatabase));
      Ini.WriteString('WebUI', 'User', JsonStr(WebUI, 'user', WebUIUser));
      Ini.WriteString('WebUI', 'Password', JsonStr(WebUI, 'password', WebUIPassword));
      Ini.WriteInteger('ESL', 'Aktiv', Ord(JsonBool(ESL, 'active', ESLActive)));
      Ini.WriteString('ESL', 'Host', JsonStr(ESL, 'host', ESLHost));
      Ini.WriteInteger('ESL', 'Port', StrToIntDef(JsonStr(ESL, 'port', IntToStr(ESLPort)), ESLPort));
      Ini.WriteString('ESL', 'Location', JsonStr(ESL, 'location', ESLLocation));
      Ini.WriteString('ESL', 'ArticleTemplate', JsonStr(ESL, 'articleTemplate', ESLArticleTemplate));
      Ini.WriteString('ESL', 'OfferTemplate', JsonStr(ESL, 'offerTemplate', ESLOfferTemplate));
      Ini.WriteInteger('ESL', 'TimeoutMS', StrToIntDef(JsonStr(ESL, 'timeoutMs', IntToStr(ESLTimeoutMS)), ESLTimeoutMS));
      Ini.WriteInteger('RFID', 'Aktiv', Ord(JsonBool(RFID, 'active', RFIDAktiv)));
      Ini.WriteInteger('RFID', 'TagLength', StrToIntDef(JsonStr(RFID, 'tagLength', IntToStr(RFIDTagLength)), RFIDTagLength));
      Ini.WriteInteger('RFID', 'TCPPort', StrToIntDef(JsonStr(RFID, 'tcpPort', IntToStr(RFIDTCPPort)), RFIDTCPPort));
      Ini.WriteString('RFID', 'Host', JsonStr(RFID, 'host', RFIDHost));
      Ini.WriteString('RFID', 'BindIP', JsonStr(RFID, 'bindIp', RFIDBindIP));
      Ini.WriteInteger('RFID', 'Ausgangskontrolle', Ord(JsonBool(RFID, 'exitAlarmActive', RFIDExitAlarmActive)));
      Ini.WriteInteger('RFID', 'AusgangsAntenne', StrToIntDef(JsonStr(RFID, 'exitAlarmAntenna', IntToStr(RFIDExitAlarmAntenna)), RFIDExitAlarmAntenna));
      Ini.WriteInteger('RFID', 'AlarmSekunden', StrToIntDef(JsonStr(RFID, 'exitAlarmSeconds', IntToStr(RFIDExitAlarmSeconds)), RFIDExitAlarmSeconds));
      Ini.WriteInteger('RFID', 'AlarmSystemBeep', Ord(JsonBool(RFID, 'exitAlarmSystemBeep', RFIDExitAlarmSystemBeep)));
      Ini.WriteString('RFID', 'AlarmSound', JsonStr(RFID, 'exitAlarmSound', RFIDExitAlarmSound));
      Ini.WriteInteger('RFID', 'StartBeiErfassung', Ord(JsonBool(RFID, 'startOnScan', RFIDStartOnScan)));
      Ini.WriteInteger('Waage', 'Aktiv', Ord(JsonBool(Scale, 'active', ScaleActive)));
      Ini.WriteString('Waage', 'Hersteller', JsonStr(Scale, 'vendor', ScaleVendor));
      Ini.WriteString('Waage', 'Modus', JsonStr(Scale, 'mode', ScaleMode));
      Ini.WriteString('Waage', 'COM', JsonStr(Scale, 'comPort', ScaleComPort));
      Ini.WriteInteger('Waage', 'Baud', StrToIntDef(JsonStr(Scale, 'baud', IntToStr(ScaleBaud)), ScaleBaud));
      Ini.WriteString('Waage', 'Host', JsonStr(Scale, 'host', ScaleHost));
      Ini.WriteInteger('Waage', 'Port', StrToIntDef(JsonStr(Scale, 'port', IntToStr(ScaleTCPPort)), ScaleTCPPort));
      Ini.WriteString('Waage', 'Request', JsonStr(Scale, 'request', ScaleRequest));
      Ini.WriteInteger('Waage', 'TimeoutMS', StrToIntDef(JsonStr(Scale, 'timeoutMs', IntToStr(ScaleTimeoutMS)), ScaleTimeoutMS));
      Ini.WriteInteger('Labeling', 'EAN_TagInfo', Ord(JsonBool(Labeling, 'eanWriteTagInfo', EANLabelWriteTagInfo)));
      Ini.WriteString('Labeling', 'Drucker', JsonStr(Labeling, 'printer', LabelDrucker));
      Ini.WriteString('Labeling', 'DruckerHost', JsonStr(Labeling, 'printerHost', LabelDruckerHost));
      Ini.WriteInteger('Labeling', 'DruckerPort', StrToIntDef(JsonStr(Labeling, 'printerPort', IntToStr(LabelDruckerPort)), LabelDruckerPort));
    finally
      Ini.Free;
    end;
    Load;
  finally
    V.Free;
  end;
end;
function TSCOConfig.AsJson: string;
begin
  Result :=
    '{' +
      '"eanRules":"' + JS(EANRules) + '",' +
      '"customer":"' + JS(Kunde) + '",' +
      '"subtitle":"' + JS(Subtitle) + '",' +
      '"phone":"' + JS(Telefon) + '",' +
      '"address":"' + JS(Adresse) + '",' +
      '"logo":"' + JS(Logo) + '",' +
      '"description":"' + JS(Beschreibung) + '",' +
      '"kundenNr":' + IntToStr(KundenNr) + ',' +
      '"nlKey":' + IntToStr(NLKey) + ',' +
      '"demoMode":' + BoolJson(DemoModus) + ',' +
      '"demoWriteJournal":' + BoolJson(DemoBonjournalSchreiben) + ',' +
      '"demoWriteWebUI":' + BoolJson(DemoWebUISchreiben) + ',' +
      '"manualProducts":' + BoolJson(ManuelleArtikel) + ',' +
      '"theme":{' +
        '"green":"' + JS(FarbeHaupt) + '",' +
        '"dark":"' + JS(FarbeDunkel) + '",' +
        '"dark2":"#0c1824",' +
        '"accent":"' + JS(FarbeAkzent) + '"' +
      '},' +
      '"payment":{' +
        '"cash":' + BoolJson(PaymentBar) + ',' +
        '"ec":' + BoolJson(PaymentEC) + ',' +
        '"customer":' + BoolJson(PaymentKundenkarte) + ',' +
        '"coupon":' + BoolJson(PaymentGutschein) +
      '},' +
      '"receipt":{' +
        '"autoPrint":' + BoolJson(BonAutoDruck) + ',' +
        '"printer":"' + JS(BonDrucker) + '",' +
        '"widthMm":' + IntToStr(BonBreiteMM) + ',' +
        '"leftMarginMm":' + StringReplace(FormatFloat('0.0', BonRandLinksMM), ',', '.', [rfReplaceAll]) +
      '},' +
      '"tse":{' +
        '"active":' + BoolJson(TSEAktiv) + ',' +
        '"provider":"' + JS(TSEProvider) + '",' +
        '"devicePath":"' + JS(TSEDevicePath) + '",' +
        '"apiUrl":"' + JS(TSEApiUrl) + '",' +
        '"clientId":"' + JS(TSEClientId) + '",' +
        '"serial":"' + JS(TSESerial) + '",' +
        '"inactiveText":"' + JS(TSEInactiveText) + '",' +
        '"ustId":"' + JS(UStId) + '"' +
      '},' +      '"rating":{' +
        '"active":' + BoolJson(BewertungAktiv) + ',' +
        '"questions":[' +
          '"' + JS(BewertungFrage1) + '",' +
          '"' + JS(BewertungFrage2) + '",' +
          '"' + JS(BewertungFrage3) + '",' +
          '"' + JS(BewertungFrage4) + '"' +
        ']' +
      '},' +
      '"zvt":{' +
        '"exe":"' + JS(ZVT_ExePath) + '",' +
        '"host":"' + JS(ZVT_Host) + '",' +
        '"kasse":' + IntToStr(ZVT_Kasse) + ',' +
        '"port":' + IntToStr(ZVT_Port) + ',' +
        '"lizenz":"' + JS(ZVT_Lizenz) + '",' +
        '"test":' + BoolJson(ZVT_Test) + ',' +
        '"dialog":' + IntToStr(ZVT_Dialog) + ',' +
        '"kassedruck":' + IntToStr(ZVT_Kassedruck) +
      '},' +
      '"rfid":{' +
        '"active":' + BoolJson(RFIDAktiv) + ',' +
        '"tagLength":' + IntToStr(RFIDTagLength) + ',' +
        '"tcpPort":' + IntToStr(RFIDTCPPort) + ',' +
        '"host":"' + JS(RFIDHost) + '",' +
        '"bindIp":"' + JS(RFIDBindIP) + '",' +
        '"exitAlarmActive":' + BoolJson(RFIDExitAlarmActive) + ',' +
        '"exitAlarmAntenna":' + IntToStr(RFIDExitAlarmAntenna) + ',' +
        '"exitAlarmSeconds":' + IntToStr(RFIDExitAlarmSeconds) + ',' +
        '"exitAlarmSystemBeep":' + BoolJson(RFIDExitAlarmSystemBeep) + ',' +
        '"exitAlarmSound":"' + JS(RFIDExitAlarmSound) + '",' +
        '"startOnScan":' + BoolJson(RFIDStartOnScan) +
      '},' +
      '"scale":{' +
        '"active":' + BoolJson(ScaleActive) + ',' +
        '"vendor":"' + JS(ScaleVendor) + '",' +
        '"mode":"' + JS(ScaleMode) + '",' +
        '"comPort":"' + JS(ScaleComPort) + '",' +
        '"baud":' + IntToStr(ScaleBaud) + ',' +
        '"host":"' + JS(ScaleHost) + '",' +
        '"port":' + IntToStr(ScaleTCPPort) + ',' +
        '"request":"' + JS(ScaleRequest) + '",' +
        '"timeoutMs":' + IntToStr(ScaleTimeoutMS) +
      '},' +
      '"labeling":{' +
        '"checkEANMod10":' + BoolJson(CheckEANMod10) + ',' +
        '"eanLabel":' + BoolJson(EnableEANLabel) + ',' +
        '"eanWriteTagInfo":' + BoolJson(EANLabelWriteTagInfo) + ',' +
        '"rfidLabel":' + BoolJson(EnableRFIDLabel) + ',' +
        '"rfidEncode":' + BoolJson(EnableRFIDEncode) + ',' +
        '"tagLength":' + IntToStr(LabelingTagLength) + ',' +
        '"rfidTagLength":' + IntToStr(LabelingTagLength) + ',' +
        '"printer":"' + JS(LabelDrucker) + '",' +
        '"printerHost":"' + JS(LabelDruckerHost) + '",' +
        '"printerPort":' + IntToStr(LabelDruckerPort) + ',' +
        '"start":"' + JS(LabelingStartMode) + '"' +
      '},' +
      '"journal":{' +
        '"filialId":"' + JS(BonjournalFilialId) + '"' +
      '},' +
      '"webui":{' +
        '"active":' + BoolJson(WebUIAktiv) + ',' +
        '"host":"' + JS(WebUIHost) + '",' +
        '"port":' + IntToStr(WebUIPort) + ',' +
        '"database":"' + JS(WebUIDatabase) + '",' +
        '"user":"' + JS(WebUIUser) + '"' +
      '},' +
      '"database":{' +
        '"host":"' + JS(DBHost) + '",' +
        '"port":' + IntToStr(DBPort) + ',' +
        '"database":"' + JS(DBFirebird) + '",' +
        '"user":"' + JS(DBUser) + '",' +
        '"password":"' + JS(DBPassword) + '",' +
        '"charset":"' + JS(DBCharset) + '"' +
      '},' +
      '"esl":{' +
        '"active":' + BoolJson(ESLActive) + ',' +
        '"host":"' + JS(ESLHost) + '",' +
        '"port":' + IntToStr(ESLPort) + ',' +
        '"location":"' + JS(ESLLocation) + '",' +
        '"articleTemplate":"' + JS(ESLArticleTemplate) + '",' +
        '"offerTemplate":"' + JS(ESLOfferTemplate) + '",' +
        '"timeoutMs":' + IntToStr(ESLTimeoutMS) +
      '},' +
      '"dailyClose":{' +
        '"active":' + BoolJson(DailyCloseActive) + ',' +
        '"time":"' + JS(DailyCloseTime) + '",' +
        '"zvt":' + BoolJson(DailyCloseZVT) + ',' +
        '"cashlogy":' + BoolJson(DailyCloseCashLogy) +
      '},' +
      '"cashlogy":{' +
        '"exe":"' + JS(CashLogyConnectorExe) + '",' +
        '"host":"' + JS(CashLogyConnectorHost) + '",' +
        '"port":' + IntToStr(CashLogyConnectorPort) +
      '}' +
    '}';
end;
initialization
  SCOConfig := TSCOConfig.Create;
  SCOConfig.Load;
finalization
  SCOConfig.Free;
end.
