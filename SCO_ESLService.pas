unit SCO_ESLService;

interface

uses
  System.SysUtils;

function ESLConfigJson: string;
function ESLConfigSaveJson(const Body: string): string;
function ESLArticlesJson(const Search: string): string;
function ESLOffersJson: string;
function ESLAssignmentsJson: string;
function ESLAssignmentSaveJson(const Body: string): string;
function ESLAssignmentDeleteJson(const LabelID: string): string;
function ESLSizesJson: string;
function ESLSizeSaveJson(const Body: string): string;
function ESLSizeDeleteJson(const ID: string): string;
function ESLTemplatesJson: string;
function ESLTemplateGetJson(const ID: string): string;
function ESLTemplateSaveJson(const Body: string): string;
function ESLTemplateDeleteJson(const ID: string): string;
function ESLSendJson(const Body: string): string;
function ESLRawJson(const Body: string): string;
function ESLQueueJson(const QueueID: string): string;
function ESLStatusJson: string;

implementation

uses
  System.Classes, System.IOUtils, System.JSON, System.Types, System.IniFiles,
  System.StrUtils, Data.DB,
  FireDAC.Comp.Client, IdTCPClient, IdGlobal,
  SCO_DB, SCO_CONFIG, SCO_Logger;

function JS(const S: string): string;
begin
  Result := JsonEscape(S);
end;

function BoolJson(Value: Boolean): string;
begin
  if Value then Result := 'true' else Result := 'false';
end;

function PriceJson(Value: Double): string;
begin
  Result := StringReplace(FormatFloat('0.00', Value), ',', '.', [rfReplaceAll]);
end;

function FloatJson(Value: Double): string;
begin
  Result := StringReplace(FormatFloat('0.###', Value), ',', '.', [rfReplaceAll]);
end;

function FieldStr(Q: TFDQuery; const Name: string): string;
begin
  Result := '';
  if (Q.FindField(Name) <> nil) and not Q.FieldByName(Name).IsNull then
    Result := Q.FieldByName(Name).AsString;
end;

function FieldFloat(Q: TFDQuery; const Name: string): Double;
begin
  Result := 0;
  if (Q.FindField(Name) <> nil) and not Q.FieldByName(Name).IsNull then
    Result := Q.FieldByName(Name).AsFloat;
end;

function FieldDate(Q: TFDQuery; const Name: string): string;
begin
  Result := '';
  if (Q.FindField(Name) = nil) or Q.FieldByName(Name).IsNull then
    Exit;
  try
    Result := FormatDateTime('yyyy-mm-dd', Q.FieldByName(Name).AsDateTime);
  except
    Result := FieldStr(Q, Name);
  end;
end;

function JsonString(O: TJSONObject; const Name, Default: string): string;
var
  V: TJSONValue;
begin
  Result := Default;
  if O = nil then Exit;
  V := O.GetValue(Name);
  if V <> nil then Result := V.Value;
end;

function JsonBool(O: TJSONObject; const Name: string; Default: Boolean): Boolean;
var
  V: TJSONValue;
begin
  Result := Default;
  if O = nil then Exit;
  V := O.GetValue(Name);
  if V <> nil then
    Result := SameText(V.Value, 'true') or SameText(V.Value, '1');
end;

function JsonInt(O: TJSONObject; const Name: string; Default: Integer): Integer;
begin
  Result := StrToIntDef(JsonString(O, Name, IntToStr(Default)), Default);
end;

function JsonFloat(O: TJSONObject; const Name: string; Default: Double): Double;
begin
  Result := StrToFloatDef(StringReplace(JsonString(O, Name, FloatToStr(Default)), '.', ',', [rfReplaceAll]), Default);
end;

function SafeID(const Value: string): string;
var
  C: Char;
begin
  Result := '';
  for C in LowerCase(Trim(Value)) do
    if CharInSet(C, ['a'..'z', '0'..'9', '-', '_']) then
      Result := Result + C;
end;

function ESLRoot: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'ESL');
  ForceDirectories(Result);
end;

function ESLFolder(const Name: string): string;
begin
  Result := TPath.Combine(ESLRoot, Name);
  ForceDirectories(Result);
end;

function AssignmentPath: string;
begin
  Result := ESLFolder('Assignments');
end;

function SizePath: string;
begin
  Result := ESLFolder('Sizes');
end;

function TemplatePath: string;
begin
  Result := ESLFolder('Templates');
end;

function ReadJsonFile(const FileName: string; out O: TJSONObject): TJSONValue;
var
  Raw: string;
begin
  O := nil;
  Result := nil;
  if not TFile.Exists(FileName) then Exit;
  Raw := TFile.ReadAllText(FileName, TEncoding.UTF8);
  Result := TJSONObject.ParseJSONValue(Raw);
  if Result is TJSONObject then
    O := TJSONObject(Result);
end;

function ObjectFileList(const Folder: string): string;
var
  Files: TStringDynArray;
  F: string;
  V: TJSONValue;
  O: TJSONObject;
  First: Boolean;
begin
  Result := '[';
  First := True;
  Files := TDirectory.GetFiles(Folder, '*.json');
  for F in Files do
  begin
    V := nil;
    try
      V := ReadJsonFile(F, O);
      if O = nil then Continue;
      if not First then Result := Result + ',';
      Result := Result + O.ToJSON;
      First := False;
    except
      on E: Exception do LogError('ESL JSON LIST ' + F + ': ' + E.Message);
    end;
    V.Free;
  end;
  Result := Result + ']';
end;

procedure EnsureDefaultSizes;
var
  FileName: string;
begin
  ForceDirectories(SizePath);
  FileName := TPath.Combine(SizePath, '2-66.json');
  if not TFile.Exists(FileName) then
    TFile.WriteAllText(FileName,
      '{"id":"2-66","name":"2,66 Zoll Artikel","width":296,"height":152,"colors":"black-white-red","defaultSource":"article"}',
      TEncoding.UTF8);
  FileName := TPath.Combine(SizePath, '4-2.json');
  if not TFile.Exists(FileName) then
    TFile.WriteAllText(FileName,
      '{"id":"4-2","name":"4,2 Zoll Sonderangebot","width":400,"height":300,"colors":"black-white-red","defaultSource":"offer"}',
      TEncoding.UTF8);
end;

procedure EnsureDefaultTemplates;
var
  FileName: string;
begin
  ForceDirectories(TemplatePath);
  FileName := TPath.Combine(TemplatePath, 'article-266.json');
  if not TFile.Exists(FileName) then
    TFile.WriteAllText(FileName,
      '{"id":"article-266","name":"Artikel 2,66 Zoll","fileName":"Shelf_266.tpl","sizeId":"2-66","source":"article","fields":["ITEMNO","NAME","PRICE","PRICE100G","UNIT","INGREDIENTS"]}',
      TEncoding.UTF8);
  FileName := TPath.Combine(TemplatePath, 'offer-42.json');
  if not TFile.Exists(FileName) then
    TFile.WriteAllText(FileName,
      '{"id":"offer-42","name":"Sonderangebot 4,2 Zoll","fileName":"Offer_42.tpl","sizeId":"4-2","source":"offer","fields":["ITEMNO","NAME","NAME2","PRICE","APREIS","VALIDFROM","VALIDTO"]}',
      TEncoding.UTF8);
end;

function ESLConfigJson: string;
begin
  SCOConfig.Load;
  Result := '{"ok":true,"config":{' +
    '"active":' + BoolJson(SCOConfig.ESLActive) + ',' +
    '"host":"' + JS(SCOConfig.ESLHost) + '",' +
    '"port":' + IntToStr(SCOConfig.ESLPort) + ',' +
    '"location":"' + JS(SCOConfig.ESLLocation) + '",' +
    '"articleTemplate":"' + JS(SCOConfig.ESLArticleTemplate) + '",' +
    '"offerTemplate":"' + JS(SCOConfig.ESLOfferTemplate) + '",' +
    '"timeoutMs":' + IntToStr(SCOConfig.ESLTimeoutMS) +
  '}}';
end;

function ESLConfigSaveJson(const Body: string): string;
var
  V: TJSONValue;
  O: TJSONObject;
  Ini: TIniFile;
begin
  V := TJSONObject.ParseJSONValue(Body);
  try
    if not (V is TJSONObject) then
      Exit('{"ok":false,"message":"Ungueltige JSON-Daten."}');
    O := TJSONObject(V);
    SCOConfig.Load;
    Ini := TIniFile.Create(ExtractFilePath(ParamStr(0)) + 'config.ini');
    try
      Ini.WriteInteger('ESL', 'Aktiv', Ord(JsonBool(O, 'active', SCOConfig.ESLActive)));
      Ini.WriteString('ESL', 'Host', JsonString(O, 'host', SCOConfig.ESLHost));
      Ini.WriteInteger('ESL', 'Port', JsonInt(O, 'port', SCOConfig.ESLPort));
      Ini.WriteString('ESL', 'Location', JsonString(O, 'location', SCOConfig.ESLLocation));
      Ini.WriteString('ESL', 'ArticleTemplate', JsonString(O, 'articleTemplate', SCOConfig.ESLArticleTemplate));
      Ini.WriteString('ESL', 'OfferTemplate', JsonString(O, 'offerTemplate', SCOConfig.ESLOfferTemplate));
      Ini.WriteInteger('ESL', 'TimeoutMS', JsonInt(O, 'timeoutMs', SCOConfig.ESLTimeoutMS));
    finally
      Ini.Free;
    end;
    SCOConfig.Load;
    Result := '{"ok":true,"message":"ESL-Konfiguration gespeichert."}';
  finally
    V.Free;
  end;
end;

function IngredientsForPLU(const PLU: string): string;
var
  Q: TFDQuery;
begin
  Result := '';
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'select first 1 cast(coalesce(r.BEZEICHNUNG, '''') as varchar(1000)) as TXT ' +
      'from UC3_ARTICLES_INGREDIENTS r where cast(r.PLU_NO as varchar(30)) = :PLU';
    Q.ParamByName('PLU').AsString := PLU;
    Q.Open;
    if not Q.IsEmpty then
      Result := FieldStr(Q, 'TXT');
  except
    on E: Exception do LogError('ESL INGREDIENTS ERROR: ' + E.Message);
  end;
  Q.Free;
end;

function ESLArticlesJson(const Search: string): string;
var
  Q: TFDQuery;
  First: Boolean;
  S, PLU, UnitText, Ingredients: string;
  Price: Double;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    S := Trim(Search);
        if S = '' then
      Q.SQL.Text :=
        'select first 300 FILIAL_ID, STATUS, DEPARTMENT_NO, PLU_NO, UAN, "NAME", SHORTNAME, MATCHCODE, ' +
        'PRICE1, PRICE2, ARTICLE_GROUP_NO, VAT1_NO, VAT2_NO, PRICE_FLAG, LOCKED_FLAG, DISCOUNT_FLAG, ' +
        'TARE_NO, PLU_TYPE, LAST_CHANGE ' +
        'from UC3_ARTICLES r ' +
        'order by "NAME"'
    else
    begin
      Q.SQL.Text :=
        'select first 300 FILIAL_ID, STATUS, DEPARTMENT_NO, PLU_NO, UAN, "NAME", SHORTNAME, MATCHCODE, ' +
        'PRICE1, PRICE2, ARTICLE_GROUP_NO, VAT1_NO, VAT2_NO, PRICE_FLAG, LOCKED_FLAG, DISCOUNT_FLAG, ' +
        'TARE_NO, PLU_TYPE, LAST_CHANGE ' +
        'from UC3_ARTICLES r ' +
        'where cast(PLU_NO as varchar(30)) = :PLU or coalesce(UAN, '''') = :PLU or ' +
        'upper(coalesce("NAME", '''')) like :QLIKE or upper(coalesce(SHORTNAME, '''')) like :QLIKE ' +
        'order by "NAME"';
      Q.ParamByName('PLU').AsString := S;
      Q.ParamByName('QLIKE').AsString := '%' + UpperCase(S) + '%';
    end;
    Q.Open;
    Result := '[';
    First := True;
    while not Q.Eof do
    begin
      PLU := FieldStr(Q, 'PLU_NO');
      Price := FieldFloat(Q, 'PRICE1') / 100;
      UnitText := 'Stck';
      if SameText(FieldStr(Q, 'PRICE_FLAG'), '1') or SameText(FieldStr(Q, 'PLU_TYPE'), '1') then
        UnitText := 'kg';
      Ingredients := IngredientsForPLU(PLU);
      if not First then Result := Result + ',';
      Result := Result + '{' +
        '"source":"article",' +
        '"id":"' + JS(PLU) + '",' +
        '"filialId":"' + JS(FieldStr(Q, 'FILIAL_ID')) + '",' +
        '"plu":"' + JS(PLU) + '",' +
        '"ean":"' + JS(FieldStr(Q, 'UAN')) + '",' +
        '"name":"' + JS(FieldStr(Q, 'NAME')) + '",' +
        '"shortName":"' + JS(FieldStr(Q, 'SHORTNAME')) + '",' +
        '"matchcode":"' + JS(FieldStr(Q, 'MATCHCODE')) + '",' +
        '"price":' + PriceJson(Price) + ',' +
        '"price2":' + PriceJson(FieldFloat(Q, 'PRICE2') / 100) + ',' +
        '"price100g":' + PriceJson(Price / 10) + ',' +
        '"unit":"' + JS(UnitText) + '",' +
        '"group":"' + JS(FieldStr(Q, 'ARTICLE_GROUP_NO')) + '",' +
        '"ingredients":"' + JS(Ingredients) + '",' +
        '"locked":' + BoolJson(FieldStr(Q, 'LOCKED_FLAG') <> '0') + ',' +
        '"lastChange":"' + JS(FieldDate(Q, 'LAST_CHANGE')) + '"' +
      '}';
      First := False;
      Q.Next;
    end;
    Result := Result + ']';
  except
    on E: Exception do
    begin
      LogError('ESL ARTICLES ERROR: ' + E.Message);
      Result := '[]';
    end;
  end;
  Q.Free;
end;

function ESLOffersJson: string;
var
  Q: TFDQuery;
  First: Boolean;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'select first 300 h.ID, h.NL_KEY, h.NUMMER, h.BEZEICHNUNG as OFFERNAME, h.VON, h.BIS, h.KW, ' +
      'p.LFDNO, p.ELENO, p.BEZEICHNUNG, p.BEZEICHNUNG2, p.PREIS, p.ME, p.STATUS, p.APREIS ' +
      'from SONDERANGEBOTE h join SONDERANGEBOTEPOS p on p.ID = h.ID ' +
      'order by h.VON desc, p.LFDNO';
    Q.Open;
    Result := '[';
    First := True;
    while not Q.Eof do
    begin
      if not First then Result := Result + ',';
      Result := Result + '{' +
        '"source":"offer",' +
        '"id":"' + JS(FieldStr(Q, 'ID') + '-' + FieldStr(Q, 'LFDNO')) + '",' +
        '"offerId":"' + JS(FieldStr(Q, 'ID')) + '",' +
        '"lfdno":"' + JS(FieldStr(Q, 'LFDNO')) + '",' +
        '"plu":"' + JS(FieldStr(Q, 'ELENO')) + '",' +
        '"number":"' + JS(FieldStr(Q, 'NUMMER')) + '",' +
        '"offerName":"' + JS(FieldStr(Q, 'OFFERNAME')) + '",' +
        '"name":"' + JS(FieldStr(Q, 'BEZEICHNUNG')) + '",' +
        '"name2":"' + JS(FieldStr(Q, 'BEZEICHNUNG2')) + '",' +
        '"price":' + PriceJson(FieldFloat(Q, 'PREIS')) + ',' +
        '"apreis":' + PriceJson(FieldFloat(Q, 'APREIS')) + ',' +
        '"unit":"' + JS(FieldStr(Q, 'ME')) + '",' +
        '"validFrom":"' + JS(FieldDate(Q, 'VON')) + '",' +
        '"validTo":"' + JS(FieldDate(Q, 'BIS')) + '",' +
        '"kw":"' + JS(FieldStr(Q, 'KW')) + '"' +
      '}';
      First := False;
      Q.Next;
    end;
    Result := Result + ']';
  except
    on E: Exception do
    begin
      LogError('ESL OFFERS ERROR: ' + E.Message);
      Result := '[]';
    end;
  end;
  Q.Free;
end;

function ESLAssignmentsJson: string;
begin
  Result := ObjectFileList(AssignmentPath);
end;

function ESLAssignmentSaveJson(const Body: string): string;
var
  V: TJSONValue;
  O: TJSONObject;
  LabelID, FileName: string;
begin
  V := TJSONObject.ParseJSONValue(Body);
  try
    if not (V is TJSONObject) then Exit('{"ok":false,"message":"Ungueltige JSON-Daten."}');
    O := TJSONObject(V);
    LabelID := SafeID(JsonString(O, 'labelId', ''));
    if LabelID = '' then Exit('{"ok":false,"message":"Label-ID fehlt."}');
    FileName := TPath.Combine(AssignmentPath, LabelID + '.json');
    TFile.WriteAllText(FileName, O.ToJSON, TEncoding.UTF8);
    Result := '{"ok":true,"message":"Preisschild gespeichert.","labelId":"' + JS(LabelID) + '"}';
  finally
    V.Free;
  end;
end;

function ESLAssignmentDeleteJson(const LabelID: string): string;
var
  FileName, Key: string;
begin
  Key := SafeID(LabelID);
  FileName := TPath.Combine(AssignmentPath, Key + '.json');
  if (Key <> '') and TFile.Exists(FileName) then
    TFile.Delete(FileName);
  Result := '{"ok":true,"message":"Preisschild geloescht."}';
end;

function ESLSizesJson: string;
begin
  EnsureDefaultSizes;
  Result := ObjectFileList(SizePath);
end;

function ESLSizeSaveJson(const Body: string): string;
var
  V: TJSONValue;
  O: TJSONObject;
  ID: string;
begin
  V := TJSONObject.ParseJSONValue(Body);
  try
    if not (V is TJSONObject) then Exit('{"ok":false,"message":"Ungueltige JSON-Daten."}');
    O := TJSONObject(V);
    ID := SafeID(JsonString(O, 'id', ''));
    if ID = '' then
    begin
      ID := 'size-' + FormatDateTime('yyyymmdd-hhnnsszzz', Now);
      O.AddPair('id', ID);
    end;
    TFile.WriteAllText(TPath.Combine(SizePath, ID + '.json'), O.ToJSON, TEncoding.UTF8);
    Result := '{"ok":true,"message":"Displaygroesse gespeichert.","id":"' + JS(ID) + '"}';
  finally
    V.Free;
  end;
end;

function ESLSizeDeleteJson(const ID: string): string;
var
  FileName, Key: string;
begin
  Key := SafeID(ID);
  FileName := TPath.Combine(SizePath, Key + '.json');
  if (Key <> '') and TFile.Exists(FileName) then
    TFile.Delete(FileName);
  Result := '{"ok":true,"message":"Displaygroesse geloescht."}';
end;

function ESLTemplatesJson: string;
begin
  EnsureDefaultTemplates;
  Result := ObjectFileList(TemplatePath);
end;

function ESLTemplateGetJson(const ID: string): string;
var
  FileName, Key: string;
begin
  EnsureDefaultTemplates;
  Key := SafeID(ID);
  FileName := TPath.Combine(TemplatePath, Key + '.json');
  if (Key = '') or not TFile.Exists(FileName) then
    Exit('{"ok":false,"message":"ESL-Template nicht gefunden."}');
  Result := TFile.ReadAllText(FileName, TEncoding.UTF8);
end;

function ESLTemplateSaveJson(const Body: string): string;
var
  V: TJSONValue;
  O: TJSONObject;
  ID: string;
begin
  V := TJSONObject.ParseJSONValue(Body);
  try
    if not (V is TJSONObject) then Exit('{"ok":false,"message":"Ungueltige JSON-Daten."}');
    O := TJSONObject(V);
    ID := SafeID(JsonString(O, 'id', ''));
    if ID = '' then
    begin
      ID := 'template-' + FormatDateTime('yyyymmdd-hhnnsszzz', Now);
      O.AddPair('id', ID);
    end;
    TFile.WriteAllText(TPath.Combine(TemplatePath, ID + '.json'), O.ToJSON, TEncoding.UTF8);
    Result := '{"ok":true,"message":"ESL-Template gespeichert.","id":"' + JS(ID) + '"}';
  finally
    V.Free;
  end;
end;

function ESLTemplateDeleteJson(const ID: string): string;
var
  FileName, Key: string;
begin
  Key := SafeID(ID);
  FileName := TPath.Combine(TemplatePath, Key + '.json');
  if (Key <> '') and TFile.Exists(FileName) then
    TFile.Delete(FileName);
  Result := '{"ok":true,"message":"ESL-Template geloescht."}';
end;

function FindTemplateFileName(const ID, Fallback: string): string;
var
  V: TJSONValue;
  O: TJSONObject;
  Key, FileName: string;
begin
  Result := Fallback;
  Key := SafeID(ID);
  if Key = '' then Exit;
  V := nil;
  try
    V := ReadJsonFile(TPath.Combine(TemplatePath, Key + '.json'), O);
    if O <> nil then
      Result := JsonString(O, 'fileName', Result);
  finally
    V.Free;
  end;
end;

function ReadArticleObject(const PLU: string; out Obj: TJSONObject): Boolean;
var
  Q: TFDQuery;
  Price: Double;
begin
  Result := False;
  Obj := TJSONObject.Create;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'select first 1 PLU_NO, UAN, "NAME", SHORTNAME, MATCHCODE, PRICE1, PRICE2, ARTICLE_GROUP_NO, PRICE_FLAG, PLU_TYPE ' +
      'from UC3_ARTICLES where cast(PLU_NO as varchar(30)) = :PLU';
    Q.ParamByName('PLU').AsString := PLU;
    Q.Open;
    if Q.IsEmpty then Exit;
    Price := FieldFloat(Q, 'PRICE1') / 100;
    Obj.AddPair('ITEMNO', FieldStr(Q, 'PLU_NO'));
    Obj.AddPair('PLU', FieldStr(Q, 'PLU_NO'));
    Obj.AddPair('EAN', FieldStr(Q, 'UAN'));
    Obj.AddPair('NAME', FieldStr(Q, 'NAME'));
    Obj.AddPair('SHORTNAME', FieldStr(Q, 'SHORTNAME'));
    Obj.AddPair('MATCHCODE', FieldStr(Q, 'MATCHCODE'));
    Obj.AddPair('PRICE', PriceJson(Price));
    Obj.AddPair('PRICE2', PriceJson(FieldFloat(Q, 'PRICE2') / 100));
    Obj.AddPair('PRICE100G', PriceJson(Price / 10));
    Obj.AddPair('PRICEKG', PriceJson(Price));
    Obj.AddPair('UNIT', 'kg');
    Obj.AddPair('GROUP', FieldStr(Q, 'ARTICLE_GROUP_NO'));
    Obj.AddPair('INGREDIENTS', IngredientsForPLU(PLU));
    Result := True;
  finally
    Q.Free;
    if not Result then
      FreeAndNil(Obj);
  end;
end;

function ReadOfferObject(const OfferKey: string; out Obj: TJSONObject): Boolean;
var
  Q: TFDQuery;
  P: Integer;
  OfferID, LfdNo: string;
begin
  Result := False;
  Obj := TJSONObject.Create;
  P := Pos('-', OfferKey);
  if P > 0 then
  begin
    OfferID := Copy(OfferKey, 1, P - 1);
    LfdNo := Copy(OfferKey, P + 1, MaxInt);
  end
  else
  begin
    OfferID := OfferKey;
    LfdNo := '';
  end;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'select first 1 h.ID, h.NUMMER, h.BEZEICHNUNG as OFFERNAME, h.VON, h.BIS, h.KW, ' +
      'p.LFDNO, p.ELENO, p.BEZEICHNUNG, p.BEZEICHNUNG2, p.PREIS, p.ME, p.APREIS ' +
      'from SONDERANGEBOTE h join SONDERANGEBOTEPOS p on p.ID = h.ID ' +
      'where cast(h.ID as varchar(30)) = :ID and (:LFD = '''' or cast(p.LFDNO as varchar(30)) = :LFD)';
    Q.ParamByName('ID').AsString := OfferID;
    Q.ParamByName('LFD').AsString := LfdNo;
    Q.Open;
    if Q.IsEmpty then Exit;
    Obj.AddPair('ITEMNO', FieldStr(Q, 'ELENO'));
    Obj.AddPair('PLU', FieldStr(Q, 'ELENO'));
    Obj.AddPair('OFFERNO', FieldStr(Q, 'NUMMER'));
    Obj.AddPair('OFFERNAME', FieldStr(Q, 'OFFERNAME'));
    Obj.AddPair('NAME', FieldStr(Q, 'BEZEICHNUNG'));
    Obj.AddPair('NAME2', FieldStr(Q, 'BEZEICHNUNG2'));
    Obj.AddPair('PRICE', PriceJson(FieldFloat(Q, 'PREIS')));
    Obj.AddPair('APREIS', PriceJson(FieldFloat(Q, 'APREIS')));
    Obj.AddPair('UNIT', FieldStr(Q, 'ME'));
    Obj.AddPair('VALIDFROM', FieldDate(Q, 'VON'));
    Obj.AddPair('VALIDTO', FieldDate(Q, 'BIS'));
    Obj.AddPair('KW', FieldStr(Q, 'KW'));
    Result := True;
  finally
    Q.Free;
    if not Result then
      FreeAndNil(Obj);
  end;
end;

function HttpGetWithJsonBody(const Host: string; Port: Integer; const Path, Body: string;
  TimeoutMS: Integer; out StatusLine, ResponseBody: string): Boolean;
var
  TCP: TIdTCPClient;
  Line: string;
  ContentLength: Integer;
begin
  Result := False;
  StatusLine := '';
  ResponseBody := '';
  ContentLength := -1;
  TCP := TIdTCPClient.Create(nil);
  try
    TCP.Host := Host;
    TCP.Port := Port;
    TCP.ConnectTimeout := TimeoutMS;
    TCP.ReadTimeout := TimeoutMS;
    TCP.Connect;
    TCP.IOHandler.Write('GET ' + Path + ' HTTP/1.1'#13#10 +
      'Host: ' + Host + ':' + IntToStr(Port) + #13#10 +
      'Connection: close'#13#10 +
      'Content-Type: application/json; charset=utf-8'#13#10 +
      'Content-Length: ' + IntToStr(Length(TEncoding.UTF8.GetBytes(Body))) + #13#10#13#10,
      IndyTextEncoding_UTF8);
    TCP.IOHandler.Write(Body, IndyTextEncoding_UTF8);
    StatusLine := TCP.IOHandler.ReadLn(IndyTextEncoding_UTF8);
    repeat
      Line := TCP.IOHandler.ReadLn(IndyTextEncoding_UTF8);
      if Pos('content-length:', LowerCase(Line)) = 1 then
        ContentLength := StrToIntDef(Trim(Copy(Line, Pos(':', Line) + 1, MaxInt)), -1);
    until Line = '';
    if ContentLength >= 0 then
      ResponseBody := TCP.IOHandler.ReadString(ContentLength, IndyTextEncoding_UTF8)
    else
      while TCP.Connected do
        ResponseBody := ResponseBody + TCP.IOHandler.ReadString(1024, IndyTextEncoding_UTF8);
    Result := Pos(' 200 ', StatusLine) > 0;
  finally
    if TCP.Connected then TCP.Disconnect;
    TCP.Free;
  end;
end;

function SendESLEasyCommand(const Command: string; Data: TJSONObject): string;
var
  Root: TJSONObject;
  Arr: TJSONArray;
  Req, Status, Body: string;
  OK: Boolean;
begin
  SCOConfig.Load;
  Root := TJSONObject.Create;
  try
    Arr := TJSONArray.Create;
    Arr.AddElement(Data);
    Root.AddPair('command', Command);
    Root.AddPair('data', Arr);
    Req := Root.ToJSON;
    OK := HttpGetWithJsonBody(SCOConfig.ESLHost, SCOConfig.ESLPort, '/api3/esleasy',
      Req, SCOConfig.ESLTimeoutMS, Status, Body);
    LogTransaction('ESL ' + Command + ' ' + Status + ' ' + Copy(Body, 1, 240));
    Result := '{"ok":' + BoolJson(OK) + ',"request":' + Req + ',"status":"' + JS(Status) + '","responseRaw":"' + JS(Body) + '"}';
  except
    on E: Exception do
    begin
      LogError('ESL SEND ERROR: ' + E.Message);
      Result := '{"ok":false,"message":"' + JS(E.Message) + '"}';
    end;
  end;
  Root.Free;
end;

function ESLSendJson(const Body: string): string;
var
  V: TJSONValue;
  O, Data: TJSONObject;
  Source, SourceID, LabelID, TemplateID, TemplateFile, Mode: string;
  ArticleObj: TJSONObject;
  Pair: TJSONPair;
  I: Integer;
begin
  V := TJSONObject.ParseJSONValue(Body);
  try
    if not (V is TJSONObject) then Exit('{"ok":false,"message":"Ungueltige JSON-Daten."}');
    O := TJSONObject(V);
    LabelID := JsonString(O, 'labelId', '');
    if Trim(LabelID) = '' then Exit('{"ok":false,"message":"Label-ID fehlt."}');
    Source := LowerCase(JsonString(O, 'source', 'article'));
    SourceID := JsonString(O, 'sourceId', JsonString(O, 'plu', ''));
    TemplateID := JsonString(O, 'templateId', '');
    if TemplateID = '' then
      if Source = 'offer' then TemplateID := SCOConfig.ESLOfferTemplate else TemplateID := SCOConfig.ESLArticleTemplate;
    TemplateFile := FindTemplateFileName(TemplateID, TemplateID);
    if TemplateFile = '' then Exit('{"ok":false,"message":"Template fehlt."}');

    if Source = 'offer' then
      Result := BoolJson(ReadOfferObject(SourceID, ArticleObj))
    else
      Result := BoolJson(ReadArticleObject(SourceID, ArticleObj));
    if not Assigned(ArticleObj) then
      Exit('{"ok":false,"message":"Datenquelle nicht gefunden."}');

    Data := TJSONObject.Create;
    Data.AddPair('__LABELID', LabelID);
    Data.AddPair('__TEMPLATE', TemplateFile);
    if Trim(SCOConfig.ESLLocation) <> '' then
      Data.AddPair('__LOCATION', SCOConfig.ESLLocation);
    Data.AddPair('__PRIORITY', JsonString(O, 'priority', '0'));
    Mode := JsonString(O, 'priceMode', '');
    if SameText(Mode, '100g') then
      Data.AddPair('DISPLAYPRICE', JsonString(ArticleObj, 'PRICE100G', '0.00') + ' / 100 g')
    else if SameText(Mode, 'kg') then
      Data.AddPair('DISPLAYPRICE', JsonString(ArticleObj, 'PRICEKG', '0.00') + ' / kg')
    else
      Data.AddPair('DISPLAYPRICE', JsonString(ArticleObj, 'PRICE', '0.00'));
    for I := 0 to ArticleObj.Count - 1 do
    begin
      Pair := ArticleObj.Pairs[I];
      Data.AddPair(Pair.JsonString.Value, Pair.JsonValue.Value);
    end;
    ArticleObj.Free;
    Result := SendESLEasyCommand('UPDATELABEL', Data);
  finally
    V.Free;
  end;
end;

function ESLRawJson(const Body: string): string;
var
  V: TJSONValue;
  O, Data: TJSONObject;
  Command: string;
begin
  V := TJSONObject.ParseJSONValue(Body);
  try
    if not (V is TJSONObject) then Exit('{"ok":false,"message":"Ungueltige JSON-Daten."}');
    O := TJSONObject(V);
    Command := JsonString(O, 'command', 'UPDATELABEL');
    Data := O.GetValue<TJSONObject>('data');
    if Data = nil then
      Exit('{"ok":false,"message":"data-Objekt fehlt."}');
    Result := SendESLEasyCommand(Command, TJSONObject(Data.Clone));
  finally
    V.Free;
  end;
end;

function ESLQueueJson(const QueueID: string): string;
var
  Data: TJSONObject;
begin
  Data := TJSONObject.Create;
  Data.AddPair('__QUEUEID', QueueID);
  Result := SendESLEasyCommand('GETQUEUEENTRY', Data);
end;

function ESLStatusJson: string;
var
  Status, Body: string;
  OK: Boolean;
begin
  SCOConfig.Load;
  OK := HttpGetWithJsonBody(SCOConfig.ESLHost, SCOConfig.ESLPort, '/api3/esleasy',
    '{"command":"GETLOCATION","data":[{"__LOCATION":"' + JS(SCOConfig.ESLLocation) + '"}]}',
    SCOConfig.ESLTimeoutMS, Status, Body);
  Result := '{"ok":' + BoolJson(OK) + ',"status":"' + JS(Status) + '","responseRaw":"' + JS(Body) + '"}';
end;

end.








