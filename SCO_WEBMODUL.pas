unit SCO_WEBMODUL;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.IniFiles,
  Web.HTTPApp;

type
  TWebModule1 = class(TWebModule)
    procedure WebModule1DefaultHandlerAction(Sender: TObject;
      Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
  private
    procedure SendJson(Response: TWebResponse; const Json: string);
    function MimeType(const FileName: string): string;
    procedure ServeFile(Response: TWebResponse; const FileName: string);
    procedure Redirect(Response: TWebResponse; const Location: string);
    function HelpLogJson(Limit: Integer): string;
    function HelpHtml: string;
  public
  end;

var
  WebModuleClass: TComponentClass = TWebModule1;

implementation

{%CLASSGROUP 'Vcl.Controls.TControl'}

{$R *.dfm}

uses
  SCO_CONFIG,
  SCO_DB,
  SCO_ScanService,
  SCO_PaymentService,
  SCO_CashLogyService,
    SCO_ReceiptService,
SCO_LabelingService,
  SCO_LabelDesignerService,
  SCO_AdminArticleService,
  SCO_ScaleService,
  SCO_RFIDTcpService,
  SCO_SalesJournalService,
  SCO_StatisticsService,
  SCO_DailyCloseService,
  SCO_RatingService,
  SCO_LocalEventService,
  SCO_ESLService,
  SCO_Logger,
  Winapi.Windows, Winapi.ShellAPI, IdTCPClient;


function ApiBool(Value: Boolean): string;
begin
  if Value then Result := 'true' else Result := 'false';
end;

function ApiEscape(const S: string): string;
begin
  Result := S;
  Result := StringReplace(Result, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
end;

function ParseApiDate(const S:string; DefaultDate:TDateTime):TDateTime;
var Y,M,D:Integer;
begin
  Result:=DefaultDate;
  if Length(Trim(S))<>10 then Exit;
  Y:=StrToIntDef(Copy(S,1,4),0); M:=StrToIntDef(Copy(S,6,2),0); D:=StrToIntDef(Copy(S,9,2),0);
  try Result:=EncodeDate(Y,M,D); except Result:=DefaultDate; end;
end;
procedure ExitKioskModeDelayed;
begin
  TThread.CreateAnonymousThread(
    procedure
    begin
      Sleep(1500);
      try
        ShellExecute(0, 'open', 'explorer.exe', nil, nil, SW_SHOWNORMAL);
      except
      end;
      Sleep(300);
      try
        ShellExecute(0, 'open', 'taskkill.exe', '/IM msedge.exe /F', nil, SW_HIDE);
      except
      end;
    end).Start;
end;
function CashLogyResultJson(const R: TCashLogyResult): string;
begin
  Result :=
    '{"ok":' + ApiBool(R.OK) +
    ',"message":"' + ApiEscape(R.StatusText) +
    '","raw":"' + ApiEscape(R.RawResponse) + '"}';
end;

function CashLogyConnectorWindowOpen: Boolean;
begin
  Result := FindWindow(nil, 'CashlogyConnector') <> 0;
end;
function TryCashLogyConnectorTcp(const Host: string; Port: Integer; out Msg: string): Boolean;
var
  TCP: TIdTCPClient;
  H: string;
begin
  Result := False;
  H := Trim(Host);
  if H = '' then
    H := '127.0.0.1';
  Msg := H + ':' + IntToStr(Port);
  TCP := TIdTCPClient.Create(nil);
  try
    TCP.Host := H;
    TCP.Port := Port;
    TCP.ConnectTimeout := 800;
    TCP.ReadTimeout := 800;
    try
      TCP.Connect;
      Result := True;
    except
      on E: Exception do
        Msg := Msg + ' -> ' + E.Message;
    end;
  finally
    if TCP.Connected then
      TCP.Disconnect;
    TCP.Free;
  end;
end;

function WaitCashLogyConnectorTcp(const Host: string; Port: Integer; out Msg: string): Boolean;
var
  I: Integer;
  P: Integer;
begin
  Result := False;
  Msg := '';
  P := Port;
  if P <= 0 then
    P := 8092;
  for I := 0 to 12 do
  begin
    if TryCashLogyConnectorTcp(Host, P, Msg) then
      Exit(True);
    Sleep(500);
  end;
end;
function StartCashLogyConnectorJson: string;
var
  ExeName, WorkDir, ProbeMsg: string;
  Code: HINST;
begin
  SCOConfig.Load;
  ExeName := Trim(SCOConfig.CashLogyConnectorExe);
  if ExeName = '' then
    Exit('{"ok":false,"message":"CashLogyConnectorExe ist nicht konfiguriert."}');
  if not FileExists(ExeName) then
    Exit('{"ok":false,"message":"CashLogy Connector nicht gefunden: ' + ApiEscape(ExeName) + '"}');

  if CashLogyConnectorWindowOpen then
    Exit('{"ok":true,"message":"CashLogy Connector laeuft bereits."}');

  if WaitCashLogyConnectorTcp(SCOConfig.CashLogyConnectorHost, SCOConfig.CashLogyConnectorPort, ProbeMsg) then
    Exit('{"ok":true,"message":"CashLogy Connector laeuft bereits und TCP ist erreichbar: ' + ApiEscape(ProbeMsg) + '"}');

  WorkDir := ExtractFilePath(ExeName);
  Code := ShellExecute(0, 'open', PChar(ExeName), nil, PChar(WorkDir), SW_SHOWNORMAL);
  if Code > 32 then
  begin
    LogTransaction('CASHLOGY ADMIN START ' + ExeName);
    if WaitCashLogyConnectorTcp(SCOConfig.CashLogyConnectorHost, SCOConfig.CashLogyConnectorPort, ProbeMsg) then
      Result := '{"ok":true,"message":"CashLogy Connector wurde gestartet und TCP ist erreichbar: ' + ApiEscape(ProbeMsg) + '"}'
    else
      Result := '{"ok":false,"message":"CashLogy Connector wurde gestartet, aber der TCP-Port ist noch nicht erreichbar. Geprueft: ' + ApiEscape(ProbeMsg) + '. Bitte pruefen, ob der Connector nur einmal laeuft und der TCP-Port korrekt/frei ist."}';
  end
  else
    Result := '{"ok":false,"message":"CashLogy Connector konnte nicht gestartet werden. Code ' + IntToStr(Code) + '"}';
end;
function AdminLoginJson(const Password: string): string;
var
  Ini: TIniFile;
  Expected: string;
begin
  Ini := TIniFile.Create(ExtractFilePath(ParamStr(0)) + 'config.ini');
  try
    Expected := Ini.ReadString('Admin', 'Passwort', '1234');
  finally
    Ini.Free;
  end;

  if Trim(Password) = Expected then
    Result := '{"ok":true,"message":"Admin freigegeben."}'
  else
    Result := '{"ok":false,"message":"Falsches Passwort."}';
end;
procedure TWebModule1.SendJson(Response: TWebResponse; const Json: string);
begin
  Response.SetCustomHeader('Access-Control-Allow-Origin', '*');
  Response.SetCustomHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  Response.SetCustomHeader('Access-Control-Allow-Headers', 'Content-Type');
  Response.ContentType := 'application/json; charset=utf-8';
  Response.Content := Json;
end;

function TWebModule1.MimeType(const FileName: string): string;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(FileName));

  if Ext = '.html' then Result := 'text/html; charset=utf-8'
  else if Ext = '.css' then Result := 'text/css; charset=utf-8'
  else if Ext = '.js' then Result := 'application/javascript; charset=utf-8'
  else if Ext = '.json' then Result := 'application/json; charset=utf-8'
  else if Ext = '.png' then Result := 'image/png'
  else if (Ext = '.jpg') or (Ext = '.jpeg') then Result := 'image/jpeg'
  else if Ext = '.gif' then Result := 'image/gif'
  else if Ext = '.svg' then Result := 'image/svg+xml'
  else if Ext = '.ico' then Result := 'image/x-icon'
  else if (Ext = '.mp3') or (Ext = '.mpr') then Result := 'audio/mpeg'
  else if Ext = '.wav' then Result := 'audio/wav'
  else if Ext = '.ogg' then Result := 'audio/ogg'
  else Result := 'application/octet-stream';
end;

procedure TWebModule1.ServeFile(Response: TWebResponse; const FileName: string);
var
  Ext: string;
begin
  Response.ContentType := MimeType(FileName);
  Ext := LowerCase(ExtractFileExt(FileName));

  if (Ext = '.png') or (Ext = '.jpg') or (Ext = '.jpeg') or
     (Ext = '.gif') or (Ext = '.ico') or (Ext = '.svg') or
     (Ext = '.mp3') or (Ext = '.mpr') or (Ext = '.wav') or (Ext = '.ogg') then
  begin
    Response.ContentStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  end
  else
  begin
    Response.Content := TFile.ReadAllText(FileName, TEncoding.UTF8);
  end;
end;

procedure TWebModule1.Redirect(Response: TWebResponse; const Location: string);
begin
  Response.StatusCode := 302;
  Response.SetCustomHeader('Location', Location);
  Response.Content := '';
end;

function TWebModule1.HelpHtml: string;
begin
  Result :=
    '<!doctype html><html lang="de"><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width, initial-scale=1">' +
    '<title>FOODWARE SCO Hilfe</title>' +
    '<style>body{font-family:Arial,sans-serif;margin:0;background:#f5f7fa;color:#17212b}' +
    'header{background:#12344d;color:white;padding:24px 32px}.wrap{max-width:1080px;margin:0 auto;padding:24px}' +
    '.card{background:white;border:1px solid #dce3ea;border-radius:8px;padding:18px;margin:14px 0}' +
    'h1{margin:0 0 8px}h2{color:#12344d}code{background:#eef3f7;padding:2px 5px;border-radius:4px}' +
    'pre{background:#17212b;color:#edf6ff;padding:14px;border-radius:6px;overflow:auto}' +
    'a{color:#0b67a3}li{margin:7px 0}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:14px}</style>' +
    '</head><body><header><div class="wrap"><h1>FOODWARE SCO Hilfe</h1><div>Labeling, RFID, EAN und Diagnose</div></div></header>' +
    '<main class="wrap">' +
    '<section class="card"><h2>Bedienung Labeling</h2><ul>' +
    '<li>Warengruppe waehlen oder Artikel per Suche, PLU oder EAN finden.</li>' +
    '<li>Bei RFID codieren oeffnet sich nach Artikelauswahl das RFID-Popup.</li>' +
    '<li>RFID-Tag auflegen. Gespeichert wird erst bei der konfigurierten TagLength.</li>' +
    '<li>Meldungen wie gespeichert oder bereits vorhanden stehen im RFID-Popup.</li>' +
    '</ul></section>' +
    '<section class="card"><h2>EAN-Codierung</h2><p>13-stellige numerische Scans gehen an <code>/api/labeling/scan</code>.</p>' +
    '<pre>XXAAAAAGGGGGC&#10;XXAAAAAPPPPPC</pre><ul>' +
    '<li>XX: Kennzahl. Gerade = Preis-EAN, ungerade = Gewichts-EAN.</li><li>AAAAA: Artikelnummer.</li>' +
    '<li>Preis wird serverseitig direkt aus VARTIKEL.VK_BRUTTO bestimmt.</li></ul></section>' +
    '<section class="card"><h2>Artikeldaten</h2>' +
    '<p>Quelle: VARTIKEL. Wichtige Felder: ELENO/NUMMER, EAN, BEZEICHNUNG, ' +
    'VK_BRUTTO, NENNGEWICHT, MHD, WG.</p>' +
    '<p>Produktbilder kommen normalerweise ueber /api/productimage?id=... aus der Datenbanktabelle ' +
    'PRODUKT_BILDER, Feld BILD. Die ID ist VARTIKEL.ID. SCO-Artikelauswahl und Labeling laden ' +
    'das Bild ueber diesen Endpunkt; fehlt es, wird ein neutrales Ersatzsymbol angezeigt.</p></section>' +
    '<section class="card"><h2>Config</h2><pre>[Labeling]&#10;CheckEANMod10=1&#10;EAN_label=0&#10;RFID_label=0&#10;RFID_encode=1&#10;start=RFID_encode&#10;TagLength=24</pre></section>' +
    '<section class="card"><h2>Pruef-Endpunkte</h2><div class="grid">' +
    '<div><b>Ping</b><br><a href="/api/ping">/api/ping</a></div>' +
    '<div><b>Config</b><br><a href="/api/help/config">/api/help/config</a></div>' +
    '<div><b>Artikel</b><br><a href="/api/help/articles?wg=0">/api/help/articles?wg=0</a></div>' +
    '<div><b>Suche</b><br><a href="/api/help/articles?q=1001">/api/help/articles?q=1001</a></div>' +
    '<div><b>Log</b><br><a href="/api/help/log?limit=120">/api/help/log?limit=120</a></div>' +
    '</div></section></main></body></html>';
end;
function TWebModule1.HelpLogJson(Limit: Integer): string;
var
  Lines: TStringList;
  FileName: string;
  I, StartIndex: Integer;
begin
  if Limit <= 0 then
    Limit := 120;
  if Limit > 1000 then
    Limit := 1000;

  FileName := ExtractFilePath(ParamStr(0)) + 'logs\sco_' + FormatDateTime('yyyy-mm-dd', Date) + '.log';
  Result := '{"ok":true,"file":"' + JsonEscape(FileName) + '","lines":[';

  Lines := TStringList.Create;
  try
    if FileExists(FileName) then
      Lines.LoadFromFile(FileName, TEncoding.UTF8);

    StartIndex := Lines.Count - Limit;
    if StartIndex < 0 then
      StartIndex := 0;

    for I := StartIndex to Lines.Count - 1 do
    begin
      if I > StartIndex then
        Result := Result + ',';
      Result := Result + '"' + JsonEscape(Lines[I]) + '"';
    end;
  finally
    Lines.Free;
  end;

  Result := Result + ']}';
end;

function ApiUsesDatabase(const Path: string): Boolean;
begin
  Result :=
    (Pos('/api/statistics', Path) = 1) or
    (Pos('/api/admin/article', Path) = 1) or
    SameText(Path, '/api/admin/database/test') or
    (Pos('/api/admin/daily-close', Path) = 1) or
    SameText(Path, '/api/groups') or
    SameText(Path, '/api/products') or
    SameText(Path, '/api/productimage') or
    SameText(Path, '/api/scan') or
    (Pos('/api/labeling/', Path) = 1) or
    (Pos('/api/esl/', Path) = 1) or
    SameText(Path, '/api/rfid/scan') or
    SameText(Path, '/api/rfid/release') or
    SameText(Path, '/api/rating/save') or
    SameText(Path, '/api/event/log') or
    SameText(Path, '/api/sale/complete');
end;

procedure TWebModule1.WebModule1DefaultHandlerAction(Sender: TObject;
  Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
var
  Path, FileName, WebRoot, EAN: string;
  ScanService: TSCOScanService;
  WG: Integer;
  Payment: TSCOPaymentService;
  PayType: string;
  AmountText: string;
  Amount: Double;
  Receipt: TSCOReceiptService;
  Sales: TSCOSalesJournalService;
  Cash: TCashLogyService;
  NeedsDB: Boolean;
begin
  Handled := True;

  Path := Request.PathInfo;
  if Path = '' then
    Path := '/';

  if (not SameText(Path, '/api/rfid/events')) and
     (not SameText(Path, '/api/rfid/scan')) and
     (not SameText(Path, '/api/products')) and
     (not SameText(Path, '/favicon.ico')) then
    LogRequest(Request.Method, Path, Request.RemoteAddr);

  if SameText(Request.Method, 'OPTIONS') then
  begin
    Response.SetCustomHeader('Access-Control-Allow-Origin', '*');
    Response.SetCustomHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    Response.SetCustomHeader('Access-Control-Allow-Headers', 'Content-Type');
    Response.StatusCode := 204;
    Exit;
  end;

  NeedsDB := ApiUsesDatabase(Path);
  if NeedsDB then
    EnterDBAccess;
  try
    try
      if SameText(Path, '/') then
    begin
      Redirect(Response, '/sco/');
      Exit;
    end;

    if SameText(Path, '/sco') then
    begin
      Redirect(Response, '/sco/');
      Exit;
    end;

    if SameText(Path, '/admin') then
    begin
      Redirect(Response, '/admin/');
      Exit;
    end;

    if SameText(Path, '/statistik') then
    begin
      Redirect(Response, '/statistik/');
      Exit;
    end;

    if SameText(Path, '/help') then
    begin
      Redirect(Response, '/help/');
      Exit;
    end;

    if SameText(Path, '/esl') then
    begin
      Redirect(Response, '/esl/');
      Exit;
    end;

    if SameText(Path, '/favicon.ico') then
    begin
      Response.StatusCode := 204;
      Exit;
    end;

    if SameText(Path, '/api/ping') then
    begin
      SendJson(Response, '{"ok":true,"service":"FOODWARE_SCO","status":"running"}');
      Exit;
    end;

    if SameText(Path, '/api/config') then
    begin
      SCOConfig.Load;
      SendJson(Response, SCOConfig.AsJson);
      Exit;
    end;

    if SameText(Path, '/api/statistics') then
    begin
      ConnectDB;
      SendJson(Response, StatisticsJson(
        StrToIntDef(Request.QueryFields.Values['days'], 30),
        Request.QueryFields.Values['from'],
        Request.QueryFields.Values['to']));
      Exit;
    end;
    if SameText(Path, '/api/esl/config') then
    begin
      if SameText(Request.Method, 'POST') then
        SendJson(Response, ESLConfigSaveJson(Request.Content))
      else
        SendJson(Response, ESLConfigJson);
      Exit;
    end;

    if SameText(Path, '/api/esl/status') then
    begin
      SendJson(Response, ESLStatusJson);
      Exit;
    end;

    if SameText(Path, '/api/esl/articles') then
    begin
      ConnectDB;
      SendJson(Response, ESLArticlesJson(Request.QueryFields.Values['q']));
      Exit;
    end;

    if SameText(Path, '/api/esl/offers') then
    begin
      ConnectDB;
      SendJson(Response, ESLOffersJson);
      Exit;
    end;

    if SameText(Path, '/api/esl/labels') then
    begin
      SendJson(Response, ESLAssignmentsJson);
      Exit;
    end;

    if SameText(Path, '/api/esl/label/save') then
    begin
      SendJson(Response, ESLAssignmentSaveJson(Request.Content));
      Exit;
    end;

    if SameText(Path, '/api/esl/label/delete') then
    begin
      SendJson(Response, ESLAssignmentDeleteJson(Request.QueryFields.Values['labelId']));
      Exit;
    end;

    if SameText(Path, '/api/esl/sizes') then
    begin
      SendJson(Response, ESLSizesJson);
      Exit;
    end;

    if SameText(Path, '/api/esl/size/save') then
    begin
      SendJson(Response, ESLSizeSaveJson(Request.Content));
      Exit;
    end;

    if SameText(Path, '/api/esl/size/delete') then
    begin
      SendJson(Response, ESLSizeDeleteJson(Request.QueryFields.Values['id']));
      Exit;
    end;

    if SameText(Path, '/api/esl/templates') then
    begin
      SendJson(Response, ESLTemplatesJson);
      Exit;
    end;

    if SameText(Path, '/api/esl/template') then
    begin
      SendJson(Response, ESLTemplateGetJson(Request.QueryFields.Values['id']));
      Exit;
    end;

    if SameText(Path, '/api/esl/template/save') then
    begin
      SendJson(Response, ESLTemplateSaveJson(Request.Content));
      Exit;
    end;

    if SameText(Path, '/api/esl/template/delete') then
    begin
      SendJson(Response, ESLTemplateDeleteJson(Request.QueryFields.Values['id']));
      Exit;
    end;

    if SameText(Path, '/api/esl/send') then
    begin
      ConnectDB;
      SendJson(Response, ESLSendJson(Request.Content));
      Exit;
    end;

    if SameText(Path, '/api/esl/raw') then
    begin
      SendJson(Response, ESLRawJson(Request.Content));
      Exit;
    end;

    if SameText(Path, '/api/esl/queue') then
    begin
      SendJson(Response, ESLQueueJson(Request.QueryFields.Values['id']));
      Exit;
    end;
    if SameText(Path, '/api/admin/database/test') then
    begin
      SendJson(Response, TestDBJson);
      Exit;
    end;
    if SameText(Path, '/api/admin/daily-close') then
    begin
      ConnectDB;
      SendJson(Response, DailyCloseListJson);
      Exit;
    end;

    if SameText(Path, '/api/admin/daily-close/run') then
    begin
      ConnectDB;
      SendJson(Response, DailyCloseRunJson(
        ParseApiDate(Request.QueryFields.Values['date'], Date-1), False));
      Exit;
    end;

    if SameText(Path, '/api/admin/daily-close/receipt') then
    begin
      ConnectDB;
      SendJson(Response, DailyCloseReceiptJson(StrToIntDef(Request.QueryFields.Values['id'], 0)));
      Exit;
    end;

    if SameText(Path, '/api/admin/daily-close/print') then
    begin
      ConnectDB;
      SendJson(Response, DailyClosePrintJson(StrToIntDef(Request.QueryFields.Values['id'], 0)));
      Exit;
    end;

    if SameText(Path, '/api/statistics/book') then
    begin
      ConnectDB;
      SendJson(Response, StatisticsMarkSentJson(
        Request.QueryFields.Values['from'],
        Request.QueryFields.Values['to']));
      Exit;
    end;

    if SameText(Path, '/api/admin/login') then
    begin
      SendJson(Response, AdminLoginJson(Request.QueryFields.Values['password']));
      Exit;
    end;


    if SameText(Path, '/api/admin/config') then
    begin
      if SameText(Request.Method, 'POST') then
      begin
        SCOConfig.SaveFromJson(Request.Content);
        SendJson(Response, '{"ok":true,"message":"Config gespeichert."}');
      end
      else
      begin
        SCOConfig.Load;
        SendJson(Response, SCOConfig.AsJson);
      end;
      Exit;
    end;

    if SameText(Path, '/api/admin/exit') then
    begin
      LogTransaction('ADMIN EDGE KIOSK EXIT requested from ' + Request.RemoteAddr);
      StopRFIDTcpService;
      ClearRFIDTcpEvents;
      ExitKioskModeDelayed;
      SendJson(Response, '{"ok":true,"message":"Edge-Kiosk wird beendet. Windows Explorer wird gestartet. FOODWARE SCO laeuft weiter."}');
      Exit;
    end;
    if SameText(Path, '/api/admin/labels') then
    begin
      SendJson(Response, LabelTemplateListJson);
      Exit;
    end;

    if SameText(Path, '/api/admin/label') then
    begin
      SendJson(Response, LabelTemplateGetJson(Request.QueryFields.Values['id']));
      Exit;
    end;

    if SameText(Path, '/api/admin/label/save') then
    begin
      SendJson(Response, LabelTemplateSaveJson(Request.Content));
      Exit;
    end;

    if SameText(Path, '/api/admin/label/delete') then
    begin
      SendJson(Response, LabelTemplateDeleteJson(Request.QueryFields.Values['id']));
      Exit;
    end;
    if SameText(Path, '/api/admin/article/lookups') then
    begin
      ConnectDB;
      SendJson(Response, AdminArticleLookupsJson);
      Exit;
    end;

    if SameText(Path, '/api/admin/articles') then
    begin
      ConnectDB;
      SendJson(Response,
        AdminArticleListJson(
          Request.QueryFields.Values['q'],
          Request.QueryFields.Values['sort'],
          Request.QueryFields.Values['dir']
        )
      );
      Exit;
    end;

    if SameText(Path, '/api/admin/article') then
    begin
      ConnectDB;
      SendJson(Response, AdminArticleGetJson(StrToIntDef(Request.QueryFields.Values['id'], 0)));
      Exit;
    end;

    if SameText(Path, '/api/admin/article/next-number') then
    begin
      ConnectDB;
      SendJson(Response, AdminArticleNextNumberJson);
      Exit;
    end;

    if SameText(Path, '/api/admin/group/save') then
    begin
      ConnectDB;
      SendJson(Response, AdminGroupSaveJson(Request.Content));
      Exit;
    end;

    if SameText(Path, '/api/admin/group/delete') then
    begin
      ConnectDB;
      SendJson(Response, AdminGroupDeleteJson(StrToIntDef(Request.QueryFields.Values['number'], 0)));
      Exit;
    end;
    if SameText(Path, '/api/admin/article/number/check') then
    begin
      ConnectDB;
      SendJson(Response, AdminArticleNumberCheckJson(
        StrToIntDef(Request.QueryFields.Values['number'], 0),
        StrToIntDef(Request.QueryFields.Values['id'], 0)
      ));
      Exit;
    end;

    if SameText(Path, '/api/admin/article/save') then
    begin
      ConnectDB;
      SendJson(Response, AdminArticleSaveJson(Request.Content));
      Exit;
    end;

    if SameText(Path, '/api/admin/article/image/save') then
    begin
      ConnectDB;
      SendJson(Response, AdminArticleImageSaveJson(StrToIntDef(Request.QueryFields.Values['id'], 0), Request.Content));
      Exit;
    end;

    if SameText(Path, '/api/admin/article/delete') then
    begin
      ConnectDB;
      SendJson(Response, AdminArticleDeleteJson(StrToIntDef(Request.QueryFields.Values['id'], 0)));
      Exit;
    end;

    if SameText(Path, '/api/admin/article/duplicate') then
    begin
      ConnectDB;
      SendJson(Response, AdminArticleDuplicateJson(StrToIntDef(Request.QueryFields.Values['id'], 0)));
      Exit;
    end;

    if SameText(Path, '/api/admin/scale/test') then
    begin
      SendJson(Response, ScaleReadWeightJson);
      Exit;
    end;
    if SameText(Path, '/api/admin/label-printer/test') then
    begin
      SendJson(Response, LabelPrinterTestJson(
        Request.QueryFields.Values['host'],
        StrToIntDef(Request.QueryFields.Values['port'], 0),
        Request.QueryFields.Values['printer']));
      Exit;
    end;

    if SameText(Path, '/api/rating/save') then
    begin
      ConnectDB;
      SendJson(Response, RatingSaveJson(Request.Content));
      Exit;
    end;

    if SameText(Path, '/api/event/log') then
    begin
      ConnectDB;
      SendJson(Response, LocalEventFromJson(Request.Content));
      Exit;
    end;

    if SameText(Path, '/api/sale/complete') then
    begin
      Sales := TSCOSalesJournalService.Create;
      try
        SendJson(Response, Sales.CompleteSaleFromJson(Request.Content));
      finally
        Sales.Free;
      end;
      Exit;
    end;

    if SameText(Path, '/api/webui/status') then
    begin
      Sales := TSCOSalesJournalService.Create;
      try
        SendJson(Response, Sales.WebStatusFromJson(Request.Content));
      finally
        Sales.Free;
      end;
      Exit;
    end;

    if SameText(Path, '/api/rfid/start') then
    begin
      SCOConfig.Load;
      if not SCOConfig.RFIDAktiv then
      begin
        SendJson(Response, '{"ok":false,"message":"RFID ist in der Config deaktiviert.","active":false}');
        Exit;
      end;
      if SameText(Request.QueryFields.Values['force'], '1') or SameText(Request.QueryFields.Values['restart'], '1') then
      begin
        RestartRFIDTcpService;
        SendJson(Response, '{"ok":true,"message":"RFID neu gestartet.","active":true,"restart":true,"host":"' + SCOConfig.RFIDHost + '","port":' + IntToStr(SCOConfig.RFIDTCPPort) + '}');
      end
      else
      begin
        StartRFIDTcpService;
        SendJson(Response, '{"ok":true,"message":"RFID gestartet.","active":true,"host":"' + SCOConfig.RFIDHost + '","port":' + IntToStr(SCOConfig.RFIDTCPPort) + '}');
      end;
      Exit;
    end;
    if SameText(Path, '/api/rfid/stop') then
    begin
      StopRFIDTcpService;
      ClearRFIDTcpEvents;
      SendJson(Response, '{"ok":true,"message":"RFID gestoppt."}');
      Exit;
    end;
    if SameText(Path, '/api/rfid/scan') then
    begin
      Sales := TSCOSalesJournalService.Create;
      try
        SendJson(Response, Sales.RfidScanJson(Request.QueryFields.Values['tag'], StrToIntDef(Request.QueryFields.Values['antenna'], 0)));
      finally
        Sales.Free;
      end;
      Exit;
    end;
    if SameText(Path, '/api/rfid/events') then
    begin
      SendJson(Response, RFIDTcpEventsJson(StrToIntDef(Request.QueryFields.Values['after'], 0)));
      Exit;
    end;
    if SameText(Path, '/api/rfid/alarm/beep') then
    begin
      TThread.CreateAnonymousThread(
        procedure
        begin
          Winapi.Windows.Beep(880, 220);
          Sleep(90);
          Winapi.Windows.Beep(660, 260);
        end
      ).Start;
      SendJson(Response, '{"ok":true,"message":"RFID-Alarm-Beep gestartet."}');
      Exit;
    end;
    if SameText(Path, '/api/rfid/alarm/sound') then
    begin
      SCOConfig.Load;
      if (Trim(SCOConfig.RFIDExitAlarmSound) <> '') and FileExists(SCOConfig.RFIDExitAlarmSound) then
      begin
        ServeFile(Response, SCOConfig.RFIDExitAlarmSound);
        Exit;
      end;
      Response.StatusCode := 404;
      SendJson(Response, '{"ok":false,"message":"RFID-Alarm-Sound nicht gefunden."}');
      Exit;
    end;
    if SameText(Path, '/api/receipt/success/sound') then
    begin
      SCOConfig.Load;
      if (Trim(SCOConfig.BonErfolgSound) <> '') and FileExists(SCOConfig.BonErfolgSound) then
      begin
        ServeFile(Response, SCOConfig.BonErfolgSound);
        Exit;
      end;
      Response.StatusCode := 404;
      SendJson(Response, '{"ok":false,"message":"Bon-Erfolg-Sound nicht gefunden."}');
      Exit;
    end;
    if SameText(Path, '/api/rfid/release') then
    begin
      Sales := TSCOSalesJournalService.Create;
      try
        SendJson(Response, Sales.RfidReleaseJson(Request.QueryFields.Values['tag']));
      finally
        Sales.Free;
      end;
      Exit;
    end;
    if SameText(Path, '/api/receipt/preview') then
    begin
      Receipt := TSCOReceiptService.Create;
      try
        SendJson(Response, Receipt.PreviewFromJson(Request.Content));
      finally
        Receipt.Free;
      end;
      Exit;
    end;
    if SameText(Path, '/api/admin/receipt/test/preview') then
    begin
      Receipt := TSCOReceiptService.Create;
      try
        SendJson(Response, Receipt.TestPreview);
      finally
        Receipt.Free;
      end;
      Exit;
    end;
    if SameText(Path, '/api/admin/receipt/test/print') then
    begin
      Receipt := TSCOReceiptService.Create;
      try
        SendJson(Response, Receipt.PrintPlainText(Request.Content));
      finally
        Receipt.Free;
      end;
      Exit;
    end;
    if SameText(Path, '/api/admin/receipt/test') then
    begin
      Receipt := TSCOReceiptService.Create;
      try
        SendJson(Response, Receipt.TestPrint);
      finally
        Receipt.Free;
      end;
      Exit;
    end;

    if SameText(Path, '/api/receipt/print') then
    begin
      Receipt := TSCOReceiptService.Create;
      try
        SendJson(Response, Receipt.PrintFromJson(Request.Content));
      finally
        Receipt.Free;
      end;
      Exit;
    end;
    if SameText(Path, '/api/receipt/design') then
    begin
      Receipt := TSCOReceiptService.Create;
      try
        SendJson(Response, Receipt.OpenDesigner);
      finally
        Receipt.Free;
      end;
      Exit;
    end;

    if SameText(Path, '/api/cashlogy/open') or SameText(Path, '/api/admin/cashlogy/open') then
    begin
      SendJson(Response, StartCashLogyConnectorJson);
      Exit;
    end;

    if SameText(Path, '/api/cashlogy/status') or SameText(Path, '/api/admin/cashlogy/status') then
    begin
      SCOConfig.Load;
      Cash := TCashLogyService.Create(SCOConfig.CashLogyConnectorHost, SCOConfig.CashLogyConnectorPort);
      try
        SendJson(Response, CashLogyResultJson(Cash.Status));
      finally
        Cash.Free;
      end;
      Exit;
    end;

    if SameText(Path, '/api/cashlogy/init') or SameText(Path, '/api/admin/cashlogy/init') then
    begin
      SCOConfig.Load;
      Cash := TCashLogyService.Create(SCOConfig.CashLogyConnectorHost, SCOConfig.CashLogyConnectorPort);
      try
        SendJson(Response, CashLogyResultJson(Cash.Init));
      finally
        Cash.Free;
      end;
      Exit;
    end;
    if SameText(Path, '/api/admin/cashlogy/backoffice') then
    begin
      SCOConfig.Load;
      Cash := TCashLogyService.Create(SCOConfig.CashLogyConnectorHost, SCOConfig.CashLogyConnectorPort);
      try
        SendJson(Response, CashLogyResultJson(Cash.Backoffice));
      finally
        Cash.Free;
      end;
      Exit;
    end;

    if SameText(Path, '/api/admin/cashlogy/money') then
    begin
      SCOConfig.Load;
      Cash := TCashLogyService.Create(SCOConfig.CashLogyConnectorHost, SCOConfig.CashLogyConnectorPort);
      try
        SendJson(Response, CashLogyResultJson(Cash.MoneyStatus));
      finally
        Cash.Free;
      end;
      Exit;
    end;

    if SameText(Path, '/api/admin/cashlogy/coins') then
    begin
      SCOConfig.Load;
      Cash := TCashLogyService.Create(SCOConfig.CashLogyConnectorHost, SCOConfig.CashLogyConnectorPort);
      try
        SendJson(Response, CashLogyResultJson(Cash.CoinStatus));
      finally
        Cash.Free;
      end;
      Exit;
    end;

    if SameText(Path, '/api/admin/cashlogy/change') then
    begin
      SCOConfig.Load;
      Cash := TCashLogyService.Create(SCOConfig.CashLogyConnectorHost, SCOConfig.CashLogyConnectorPort);
      try
        SendJson(Response, CashLogyResultJson(Cash.AddChange));
      finally
        Cash.Free;
      end;
      Exit;
    end;

    if SameText(Path, '/api/admin/cashlogy/end') then
    begin
      SCOConfig.Load;
      Cash := TCashLogyService.Create(SCOConfig.CashLogyConnectorHost, SCOConfig.CashLogyConnectorPort);
      try
        SendJson(Response, CashLogyResultJson(Cash.EndSession));
      finally
        Cash.Free;
      end;
      Exit;
    end;

    if SameText(Path, '/api/admin/cashlogy/wait') then
    begin
      SCOConfig.Load;
      Cash := TCashLogyService.Create(SCOConfig.CashLogyConnectorHost, SCOConfig.CashLogyConnectorPort);
      try
        SendJson(Response, CashLogyResultJson(Cash.WaitStatus));
      finally
        Cash.Free;
      end;
      Exit;
    end;


    if SameText(Path, '/api/groups') then
    begin
      ConnectDB;
      SendJson(Response, GetGroupsJson);
      Exit;
    end;

    if SameText(Path, '/api/products') then
    begin
      ConnectDB;
      WG := StrToIntDef(Request.QueryFields.Values['wg'], 0);
      SendJson(Response, GetProductsJson(WG));
      Exit;
    end;

  if SameText(Path, '/labeling') then
    begin
      Redirect(Response, '/labeling/');
      Exit;
    end;

    if SameText(Path, '/api/productimage') then
    begin
      ConnectDB;
      SendProductImage(Response, StrToIntDef(Request.QueryFields.Values['id'], 0));
      Exit;
    end;

    if SameText(Path, '/api/scan') then
    begin
      ConnectDB;

      EAN := Request.QueryFields.Values['ean'];
      LogTransaction('SCAN EAN=' + EAN);

      ScanService := TSCOScanService.Create(FB);
      try
        SendJson(Response, ScanService.ScanEAN(EAN));
      finally
        ScanService.Free;
      end;

      Exit;
    end;
    if SameText(Path, '/api/labeling/search') then
        begin
          ConnectDB;
          SendJson(Response, LabelingSearchJson(Request.QueryFields.Values['q']));
          Exit;
        end;

        if SameText(Path, '/api/labeling/groups') then
        begin
          ConnectDB;
          SendJson(Response, LabelingGroupsJson);
          Exit;
        end;

        if SameText(Path, '/api/labeling/taras') then
        begin
          ConnectDB;
          SendJson(Response, LabelingTarasJson);
          Exit;
        end;

        if SameText(Path, '/api/labeling/products') then
        begin
          ConnectDB;
          SendJson(Response,
            LabelingProductsJson(StrToIntDef(Request.QueryFields.Values['wg'], 0))
          );
          Exit;
        end;

        if SameText(Path, '/api/labeling/scan') then
        begin
          ConnectDB;
          EAN := Request.QueryFields.Values['ean'];
          SendJson(Response, LabelingScanJson(EAN));
          Exit;
        end;

        if SameText(Path, '/api/labeling/weight') then
        begin
          SendJson(Response, LabelingReadWeightJson);
          Exit;
        end;

        if SameText(Path, '/api/labeling/print') then
        begin
          ConnectDB;
          SendJson(Response,
            LabelingPrintJson(
              StrToIntDef(Request.QueryFields.Values['plu'], 0),
              StrToFloatDef(StringReplace(Request.QueryFields.Values['weight'], '.', ',', []), 0),
              StrToFloatDef(StringReplace(Request.QueryFields.Values['tara'], '.', ',', []), 0),
              StrToIntDef(Request.QueryFields.Values['qty'], 1),
              Request.QueryFields.Values['mhd'],
              Request.QueryFields.Values['template']
            )
          );
          Exit;
        end;

        if SameText(Path, '/api/labeling/rfid/write') then
        begin
          LogTransaction(
            'API RFID WRITE HIT PLU=' + Request.QueryFields.Values['plu'] +
            ' WEIGHT=' + Request.QueryFields.Values['weight']
          );
          SendJson(Response,
            LabelingWriteRfidJson(
              StrToIntDef(Request.QueryFields.Values['plu'], 0),
              StrToFloatDef(StringReplace(Request.QueryFields.Values['weight'], '.', ',', []), 0)
            )
          );
          Exit;
        end;


         if SameText(Path, '/api/labeling/rfid/save') then
        begin
          LogTransaction(
            'API RFID SAVE HIT PLU=' + Request.QueryFields.Values['plu'] +
            ' TAG=' + Request.QueryFields.Values['tag'] +
            ' TAGLEN=' + IntToStr(Length(Request.QueryFields.Values['tag'])) +
            ' WEIGHT=' + Request.QueryFields.Values['weight'] +
            ' PRICE=' + Request.QueryFields.Values['price'] +
            ' MHD=' + Request.QueryFields.Values['mhd'] +
            ' SOURCE=' + Request.QueryFields.Values['source'] +
            ' OVERWRITE=' + Request.QueryFields.Values['overwrite']
          );
          ConnectDB;
          SendJson(Response,
            LabelingSaveRfidJson(
              StrToIntDef(Request.QueryFields.Values['plu'], 0),
              Request.QueryFields.Values['tag'],
              Request.QueryFields.Values['mhd'],
              Request.QueryFields.Values['source'],
              StrToFloatDef(StringReplace(Request.QueryFields.Values['weight'], '.', ',', []), 0),
              StrToFloatDef(StringReplace(Request.QueryFields.Values['tara'], '.', ',', []), 0),
              StrToFloatDef(StringReplace(Request.QueryFields.Values['price'], '.', ',', []), 0),
              (Request.QueryFields.Values['overwrite'] = '1') or SameText(Request.QueryFields.Values['overwrite'], 'true')
            )
          );
          Exit;
        end;


        if SameText(Path, '/api/labeling/rfid/invalidate') then
        begin
          LogTransaction(
            'API RFID INVALIDATE HIT TAG=' + Request.QueryFields.Values['tag'] +
            ' TAGLEN=' + IntToStr(Length(Request.QueryFields.Values['tag']))
          );
          ConnectDB;
          SendJson(Response, LabelingInvalidateRfidJson(Request.QueryFields.Values['tag']));
          Exit;
        end;

        if SameText(Path, '/api/labeling/rfid/check') then
        begin
          LogTransaction(
            'API RFID CHECK HIT TAG=' + Request.QueryFields.Values['tag'] +
            ' TAGLEN=' + IntToStr(Length(Request.QueryFields.Values['tag']))
          );
          ConnectDB;
          SendJson(Response, LabelingCheckRfidJson(Request.QueryFields.Values['tag']));
          Exit;
        end;

        if SameText(Path, '/api/labeling/protocol') then
        begin
          ConnectDB;
          SendJson(Response, LabelingProtocolJson(StrToIntDef(Request.QueryFields.Values['limit'], 0)));
          Exit;
        end;

        if SameText(Path, '/api/labeling/protocol/delete') then
        begin
          ConnectDB;
          SendJson(Response, LabelingProtocolDeleteJson(StrToIntDef(Request.QueryFields.Values['id'], 0)));
          Exit;
        end;

        if SameText(Path, '/api/labeling/protocol/status') then
        begin
          ConnectDB;
          SendJson(Response, LabelingProtocolStatusJson(
            StrToIntDef(Request.QueryFields.Values['id'], 0),
            StrToIntDef(Request.QueryFields.Values['status'], 0)
          ));
          Exit;
        end;



        if SameText(Path, '/api/help/config') then
        begin
          SCOConfig.Load;
          SendJson(Response, SCOConfig.AsJson);
          Exit;
        end;

        if SameText(Path, '/api/help/articles') then
        begin
          ConnectDB;
          if Trim(Request.QueryFields.Values['q']) <> '' then
            SendJson(Response, LabelingSearchJson(Request.QueryFields.Values['q']))
          else
            SendJson(Response, LabelingProductsJson(StrToIntDef(Request.QueryFields.Values['wg'], 0)));
          Exit;
        end;

        if SameText(Path, '/api/help/log') then
        begin
          SendJson(Response, HelpLogJson(StrToIntDef(Request.QueryFields.Values['limit'], 120)));
          Exit;
        end;
    if SameText(Path, '/api/pay') or
       SameText(Path, '/api/pay/start') or
       SameText(Path, '/api/payment/start') then

    begin
      PayType := LowerCase(Trim(Request.QueryFields.Values['type']));
      AmountText := Trim(Request.QueryFields.Values['amount']);
      AmountText := StringReplace(AmountText, '.', ',', [rfReplaceAll]);
      Amount := StrToFloatDef(AmountText, 0);

      LogTransaction('PAY START type=' + PayType + ' amount=' + FloatToStr(Amount));

      Payment := TSCOPaymentService.Create;
      try
        SendJson(Response, Payment.ResultToJson(Payment.Pay(PayType, Amount)));
      finally
        Payment.Free;
      end;

      Exit;
    end;

    if Pos('..', Path) > 0 then
    begin
      Response.StatusCode := 403;
      Response.ContentType := 'text/plain; charset=utf-8';
      Response.Content := 'Zugriff verweigert';
      LogError('403 Zugriff verweigert: ' + Path);
      Exit;
    end;

    WebRoot := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)) + 'www');

    if SameText(Path, '/sco/') then
      FileName := WebRoot + 'sco\index.html'
    else if SameText(Path, '/admin/') then
      FileName := WebRoot + 'admin\index.html'
    else if SameText(Path, '/statistik/') then
      FileName := WebRoot + 'statistik\index.html'
    else if SameText(Path, '/help/') then
      FileName := WebRoot + 'help\index.html'
    else if SameText(Path, '/esl/') then
      FileName := WebRoot + 'esl\index.html'
        else if SameText(Path, '/labeling/') then
          FileName := WebRoot + 'labeling\index.html'
    else
      FileName := WebRoot + StringReplace(Copy(Path, 2, MaxInt), '/', PathDelim, [rfReplaceAll]);

    if FileExists(FileName) then
    begin
      ServeFile(Response, FileName);
      Exit;
    end;

    if SameText(Path, '/help/') then
    begin
      Response.ContentType := 'text/html; charset=utf-8';
      Response.Content := HelpHtml;
      Exit;
    end;

    Response.StatusCode := 404;
    Response.ContentType := 'text/html; charset=utf-8';
    Response.Content :=
      '<!doctype html>' +
      '<html><head><meta charset="utf-8"><title>FOODWARE SCO</title></head>' +
      '<body style="font-family:Arial;padding:40px">' +
      '<h1>Datei nicht gefunden</h1>' +
      '<p>Pfad:</p><pre>' + Path + '</pre>' +
      '<p>Datei:</p><pre>' + FileName + '</pre>' +
      '<hr>' +
      '<p><a href="/sco/">SCO starten</a></p>' +
      '<p><a href="/admin/">Admin</a></p>' +
      '<p><a href="/statistik/">Statistik</a></p>' +
      '<p><a href="/api/ping">API Ping</a></p>' +
      '</body></html>';

    LogError('404 Datei nicht gefunden: ' + FileName);

  except
    on E: Exception do
    begin
      LogError('Interner Fehler bei ' + Path + ': ' + E.ClassName + ' - ' + E.Message);

      Response.StatusCode := 500;
      Response.ContentType := 'text/plain; charset=utf-8';
      Response.Content :=
        'Interner Anwendungsfehler' + sLineBreak +
        E.Message + sLineBreak + sLineBreak +
        Path;
    end;
    end;
  finally
    if NeedsDB then
      LeaveDBAccess;
  end;
end;

end.














































