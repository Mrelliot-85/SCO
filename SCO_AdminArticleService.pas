unit SCO_AdminArticleService;

interface

uses
  System.SysUtils;

function AdminArticleListJson(const Search, SortField, SortDir: string): string;
function AdminArticleGetJson(ID: Integer): string;
function AdminArticleLookupsJson: string;
function AdminArticleSaveJson(const Body: string): string;
function AdminArticleNumberCheckJson(Number, ExcludeID: Integer): string;
function AdminArticleDeleteJson(ID: Integer): string;
function AdminArticleDuplicateJson(ID: Integer): string;
function AdminArticleImageSaveJson(ID: Integer; const Body: string): string;
function AdminArticleNextNumberJson: string;
function AdminGroupSaveJson(const Body: string): string;
function AdminGroupDeleteJson(Number: Integer): string;

implementation

uses
  System.JSON,
  System.Classes,
  System.NetEncoding,
  Data.DB,
  FireDAC.Comp.Client,
  SCO_DB,
  SCO_CONFIG,
  SCO_Logger;

function JS(const S: string): string;
begin
  Result := JsonEscape(S);
end;

function FmtFloatJson(V: Double): string;
begin
  Result := StringReplace(FormatFloat('0.###', V), ',', '.', [rfReplaceAll]);
end;

function FmtPriceJson(V: Double): string;
begin
  Result := StringReplace(FormatFloat('0.00', V), ',', '.', [rfReplaceAll]);
end;

function FieldStr(Q: TFDQuery; const Name: string): string;
begin
  Result := '';
  if (Q.FindField(Name) <> nil) and not Q.FieldByName(Name).IsNull then
    Result := Q.FieldByName(Name).AsString;
end;

function FieldInt(Q: TFDQuery; const Name: string): Integer;
begin
  Result := 0;
  if (Q.FindField(Name) <> nil) and not Q.FieldByName(Name).IsNull then
    Result := Q.FieldByName(Name).AsInteger;
end;

function FieldFloat(Q: TFDQuery; const Name: string): Double;
begin
  Result := 0;
  if (Q.FindField(Name) <> nil) and not Q.FieldByName(Name).IsNull then
    Result := Q.FieldByName(Name).AsFloat;
end;

function TableHasField(const TableName, FieldName: string): Boolean;
var
  Q: TFDQuery;
begin
  Result := False;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'select first 1 1 from RDB$RELATION_FIELDS ' +
      'where RDB$RELATION_NAME = :T and RDB$FIELD_NAME = :F';
    Q.ParamByName('T').AsString := UpperCase(TableName);
    Q.ParamByName('F').AsString := UpperCase(FieldName);
    Q.Open;
    Result := not Q.IsEmpty;
  except
    Result := False;
  end;
  Q.Free;
end;


function TableExists(const TableName: string): Boolean;
var
  Q: TFDQuery;
begin
  Result := False;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'select first 1 1 from RDB$RELATIONS ' +
      'where RDB$RELATION_NAME = :T and coalesce(RDB$SYSTEM_FLAG, 0) = 0';
    Q.ParamByName('T').AsString := UpperCase(TableName);
    Q.Open;
    Result := not Q.IsEmpty;
  except
    Result := False;
  end;
  Q.Free;
end;
function JsonPair(const Name, Value: string; Comma: Boolean = True): string;
begin
  Result := '"' + Name + '":"' + JS(Value) + '"';
  if Comma then
    Result := Result + ',';
end;

function SafeSort(const S: string): string;
begin
  Result := UpperCase(Trim(S));
  if (Result <> 'NUMMER') and (Result <> 'BEZEICHNUNG') and (Result <> 'WG') and
     (Result <> 'VK_BRUTTO') and (Result <> 'EAN') and (Result <> 'MHD') and
     (Result <> 'EINHEIT') then
    Result := 'BEZEICHNUNG';
end;

function ArticleNutritionJson(ID: Integer): string;
var
  Q: TFDQuery;
begin
  Result := '"rz_kcal":0,"rz_kjoule":0,"rz_eiweiss":0,"rz_kohlenhydrate":0,"rz_zucker":0,"rz_fett":0,"rz_fettges":0,"rz_salz":0,"rz_ballast":0';
  if not TableHasField('ARTIKEL', 'RZ_BRENNWERTKCAL') then
    Exit;

  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'select first 1 RZ_BRENNWERTKCAL, RZ_BRENNWERTKJOULE, RZ_EIWEISS, RZ_KOHLENHYDRATE, RZ_ZUCKER, ' +
      'RZ_FETT, RZ_FETTGESAETTIGT, RZ_SALZ, RZ_BALLAST from ARTIKEL where ID = :ID';
    Q.ParamByName('ID').AsInteger := ID;
    Q.Open;
    if not Q.IsEmpty then
      Result :=
        '"rz_kcal":' + FmtFloatJson(FieldFloat(Q,'RZ_BRENNWERTKCAL')) + ',' +
        '"rz_kjoule":' + FmtFloatJson(FieldFloat(Q,'RZ_BRENNWERTKJOULE')) + ',' +
        '"rz_eiweiss":' + FmtFloatJson(FieldFloat(Q,'RZ_EIWEISS')) + ',' +
        '"rz_kohlenhydrate":' + FmtFloatJson(FieldFloat(Q,'RZ_KOHLENHYDRATE')) + ',' +
        '"rz_zucker":' + FmtFloatJson(FieldFloat(Q,'RZ_ZUCKER')) + ',' +
        '"rz_fett":' + FmtFloatJson(FieldFloat(Q,'RZ_FETT')) + ',' +
        '"rz_fettges":' + FmtFloatJson(FieldFloat(Q,'RZ_FETTGESAETTIGT')) + ',' +
        '"rz_salz":' + FmtFloatJson(FieldFloat(Q,'RZ_SALZ')) + ',' +
        '"rz_ballast":' + FmtFloatJson(FieldFloat(Q,'RZ_BALLAST'));
  except
    on E: Exception do LogError('ADMIN ARTICLE NUTRITION GET ERROR: ' + E.Message);
  end;
  Q.Free;
end;

function AdminArticleListJson(const Search, SortField, SortDir: string): string;
var
  Q: TFDQuery;
  First: Boolean;
  OrderField, Dir, S: string;
begin
  SCOConfig.Load;
  OrderField := SafeSort(SortField);
  Dir := UpperCase(Trim(SortDir));
  if Dir <> 'DESC' then Dir := 'ASC';
  S := Trim(Search);

  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'select first 300 ID, NUMMER, BEZEICHNUNG, BEZEICHNUNG2, EINHEIT, ME_BEZ, WG, WG_BEZ, EAN, ' +
      'MWST_1, STANDARD_ETIKETT, MHD, LAGERTEMPERATUR, TARANR, NENNGEWICHT, VK_BRUTTO ' +
      'from VARTIKEL ' +
      'where (:Q = '''' or BEZEICHNUNG containing :Q or cast(NUMMER as varchar(30)) containing :Q or coalesce(EAN,'''') containing :Q) ' +
      'order by ' + OrderField + ' ' + Dir;
    Q.ParamByName('Q').AsString := S;
    Q.Open;

    Result := '[';
    First := True;
    while not Q.Eof do
    begin
      if not First then Result := Result + ',';
      Result := Result + '{' +
        '"id":' + IntToStr(FieldInt(Q,'ID')) + ',' +
        '"nummer":"' + JS(FieldStr(Q,'NUMMER')) + '",' +
        '"name":"' + JS(FieldStr(Q,'BEZEICHNUNG')) + '",' +
        '"name2":"' + JS(FieldStr(Q,'BEZEICHNUNG2')) + '",' +
        '"einheit":' + IntToStr(FieldInt(Q,'EINHEIT')) + ',' +
        '"unit":"' + JS(FieldStr(Q,'ME_BEZ')) + '",' +
        '"wg":' + IntToStr(FieldInt(Q,'WG')) + ',' +
        '"wgName":"' + JS(FieldStr(Q,'WG_BEZ')) + '",' +
        '"ean":"' + JS(FieldStr(Q,'EAN')) + '",' +
        '"mwst":' + IntToStr(FieldInt(Q,'MWST_1')) + ',' +
        '"mhd":' + IntToStr(FieldInt(Q,'MHD')) + ',' +
        '"temp":' + IntToStr(FieldInt(Q,'LAGERTEMPERATUR')) + ',' +
        '"taranr":' + IntToStr(FieldInt(Q,'TARANR')) + ',' +
        '"nenngewicht":' + FmtFloatJson(FieldFloat(Q,'NENNGEWICHT')) + ',' +
        '"etikett":"' + JS(FieldStr(Q,'STANDARD_ETIKETT')) + '",' +
        '"price":' + FmtPriceJson(FieldFloat(Q,'VK_BRUTTO')) + ',' +
        '"ek":0.00,' +
        '"material":0.00' +
        '}';
      First := False;
      Q.Next;
    end;
    Result := Result + ']';
  except
    on E: Exception do
    begin
      LogError('ADMIN ARTICLE LIST ERROR: ' + E.Message);
      Result := '[]';
    end;
  end;
  Q.Free;
end;

function AdminArticleGetJson(ID: Integer): string;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'select first 1 ID, NL_KEY, ELENO, NUMMER, BEZEICHNUNG, BEZEICHNUNG2, EINHEIT, ME_BEZ, HWG, WG, WG_BEZ, EAN, ' +
      'ZUTATENTEXT, MWST_1, STANDARD_ETIKETT, MHD, LAGERTEMPERATUR, TARANR, NENNGEWICHT, VK_BRUTTO ' +
      'from VARTIKEL where ID = :ID';
    Q.ParamByName('ID').AsInteger := ID;
    Q.Open;
    if Q.IsEmpty then Exit('{"ok":false,"message":"Artikel nicht gefunden."}');
    Result := '{"ok":true,"article":{' +
      '"id":' + IntToStr(FieldInt(Q,'ID')) + ',' +
      '"eleno":"' + JS(FieldStr(Q,'ELENO')) + '",' +
      '"nummer":"' + JS(FieldStr(Q,'NUMMER')) + '",' +
      JsonPair('bezeichnung', FieldStr(Q,'BEZEICHNUNG')) +
      JsonPair('bezeichnung2', FieldStr(Q,'BEZEICHNUNG2')) +
      '"einheit":' + IntToStr(FieldInt(Q,'EINHEIT')) + ',' +
      '"unit":"' + JS(FieldStr(Q,'ME_BEZ')) + '",' +
      '"hwg":' + IntToStr(FieldInt(Q,'HWG')) + ',' +
      '"wg":' + IntToStr(FieldInt(Q,'WG')) + ',' +
      '"ean":"' + JS(FieldStr(Q,'EAN')) + '",' +
      '"zutatentext":"' + JS(FieldStr(Q,'ZUTATENTEXT')) + '",' +
      '"mwst":' + IntToStr(FieldInt(Q,'MWST_1')) + ',' +
      '"standardEtikett":"' + JS(FieldStr(Q,'STANDARD_ETIKETT')) + '",' +
      '"mhd":' + IntToStr(FieldInt(Q,'MHD')) + ',' +
      '"temperatur":' + IntToStr(FieldInt(Q,'LAGERTEMPERATUR')) + ',' +
      '"taranr":' + IntToStr(FieldInt(Q,'TARANR')) + ',' +
        '"nenngewicht":' + FmtFloatJson(FieldFloat(Q,'NENNGEWICHT')) + ',' +
      '"price":' + FmtPriceJson(FieldFloat(Q,'VK_BRUTTO')) + ',' +
      '"ek":0.00,' +
      '"material":0.00,' +
      ArticleNutritionJson(ID) +
      '}}';
  except
    on E: Exception do
    begin
      LogError('ADMIN ARTICLE GET ERROR: ' + E.Message);
      Result := '{"ok":false,"message":"' + JS(E.Message) + '"}';
    end;
  end;
  Q.Free;
end;

function SimpleListJson(const SQL, IdField, NameField: string): string;
var
  Q: TFDQuery;
  First: Boolean;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text := SQL;
    Q.Open;
    Result := '[';
    First := True;
    while not Q.Eof do
    begin
      if not First then Result := Result + ',';
      Result := Result + '{"id":' + IntToStr(FieldInt(Q,IdField)) + ',"name":"' + JS(FieldStr(Q,NameField)) + '"}';
      First := False;
      Q.Next;
    end;
    Result := Result + ']';
  except
    on E: Exception do
    begin
      LogError('ADMIN ARTICLE LOOKUP ERROR: ' + E.Message);
      Result := '[]';
    end;
  end;
  Q.Free;
end;

function AdminArticleLookupsJson: string;
var
  UnitSql: string;
begin
  if TableExists('EINHEIT') then
    UnitSql := 'select NUMMER, KURZBEZ from EINHEIT where coalesce(KZ_GESPERRT,''F'') <> ''T'' order by NUMMER'
  else
    UnitSql := 'select NUMMER, KURZBEZ from ME where coalesce(KZ_GESPERRT,''F'') <> ''T'' order by NUMMER';

  Result := '{' +
    '"groups":' + GetGroupsJson + ',' +
    '"temperatures":' + SimpleListJson('select NUMMER, BEZEICHNUNG from TEMPERATURTEXTE order by NUMMER','NUMMER','BEZEICHNUNG') + ',' +
    '"mwst":' + SimpleListJson('select NUMMER, BEZEICHNUNG from MWST order by NUMMER','NUMMER','BEZEICHNUNG') + ',' +
    '"units":' + SimpleListJson(UnitSql,'NUMMER','KURZBEZ') + ',' +
    '"taras":' + SimpleListJson('select NUMMER, BEZEICHNUNG from TARAS order by REIHENFOLGE, NUMMER','NUMMER','BEZEICHNUNG') +
    '}';
end;

procedure AddSet(var SQL: string; const FieldName, ParamName: string; var First: Boolean);
begin
  if not TableHasField('ARTIKEL', FieldName) then Exit;
  if not First then SQL := SQL + ', ';
  SQL := SQL + FieldName + ' = :' + ParamName;
  First := False;
end;

procedure AddInsertField(var Fields, Values: string; const FieldName, ParamName: string;
  var First: Boolean);
begin
  if not TableHasField('ARTIKEL', FieldName) then Exit;
  if not First then
  begin
    Fields := Fields + ', ';
    Values := Values + ', ';
  end;
  Fields := Fields + FieldName;
  Values := Values + ':' + ParamName;
  First := False;
end;
procedure SetParam(Q: TFDQuery; const Name: string; V: TJSONValue; const Kind: string);
begin
  if Q.Params.FindParam(Name) = nil then Exit;
  if V = nil then begin Q.ParamByName(Name).Clear; Exit; end;
  if SameText(Kind, 'float') then Q.ParamByName(Name).AsFloat := StrToFloatDef(StringReplace(V.Value,'.',',',[rfReplaceAll]),0)
  else if SameText(Kind, 'int') then Q.ParamByName(Name).AsInteger := StrToIntDef(V.Value,0)
  else Q.ParamByName(Name).AsString := V.Value;
end;

function AdminArticleNumberCheckJson(Number, ExcludeID: Integer): string;
var Q: TFDQuery; ExistingID: Integer;
begin
  if Number <= 0 then Exit('{"ok":false,"available":false,"message":"Bitte eine gueltige Artikelnummer eingeben."}');
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text := 'select first 1 ID from ARTIKEL where NL_KEY = :NLKEY and (NUMMER = :NUMMER or ELENO = :NUMMER) and ID <> :ID';
    Q.ParamByName('NLKEY').AsInteger := SCOConfig.NLKey;
    Q.ParamByName('NUMMER').AsInteger := Number;
    Q.ParamByName('ID').AsInteger := ExcludeID;
    Q.Open;
    if Q.IsEmpty then
      Result := '{"ok":true,"available":true,"message":"Artikelnummer ist frei."}'
    else
    begin
      ExistingID := Q.FieldByName('ID').AsInteger;
      Result := '{"ok":true,"available":false,"existingId":' + IntToStr(ExistingID) + ',"message":"Artikelnummer ist bereits vergeben."}';
    end;
  except
    on E: Exception do begin LogError('ADMIN ARTICLE NUMBER CHECK ERROR: ' + E.Message); Result := '{"ok":false,"available":false,"message":"' + JS(E.Message) + '"}'; end;
  end;
  Q.Free;
end;

function AdminArticleSaveJson(const Body: string): string;
var
  O: TJSONObject;
  ID, Number: Integer;
  Q: TFDQuery;
  SQL, Fields, Values: string;
  First: Boolean;
begin
  O := TJSONObject.ParseJSONValue(Body) as TJSONObject;
  if O = nil then Exit('{"ok":false,"message":"Ungueltige Artikeldaten."}');
  Q := TFDQuery.Create(nil);
  try
    ID := StrToIntDef(O.GetValue<string>('id','0'),0);
    Number := StrToIntDef(O.GetValue<string>('nummer','0'),0);
    if Number <= 0 then raise Exception.Create('Bitte eine gueltige Artikelnummer eingeben.');
    Q.Connection := FB;
    Q.SQL.Text := 'select first 1 ID from ARTIKEL where NL_KEY = :NLKEY and (NUMMER = :NUMMER or ELENO = :NUMMER) and ID <> :ID';
    Q.ParamByName('NLKEY').AsInteger := SCOConfig.NLKey;
    Q.ParamByName('NUMMER').AsInteger := Number;
    Q.ParamByName('ID').AsInteger := ID;
    Q.Open;
    if not Q.IsEmpty then raise Exception.Create('Artikelnummer ' + IntToStr(Number) + ' ist bereits vergeben.');
    Q.Close;
    First := True;
    if ID > 0 then
    begin
      SQL := 'update ARTIKEL set ';
      AddSet(SQL,'ELENO','ELENO',First); AddSet(SQL,'NUMMER','NUMMER',First);
      AddSet(SQL,'BEZEICHNUNG','BEZ',First); AddSet(SQL,'BEZEICHNUNG2','BEZ2',First);
      AddSet(SQL,'MHD','MHD',First); AddSet(SQL,'LAGERTEMPERATUR','TEMP',First);
      AddSet(SQL,'WG','WG',First); AddSet(SQL,'MWST_1','MWST',First); AddSet(SQL,'EAN','EAN',First);
      AddSet(SQL,'ZUTATENTEXT','ZUTATEN',First); AddSet(SQL,'TARANR','TARA',First); AddSet(SQL,'NENNGEWICHT','NENNGEWICHT',First);
      AddSet(SQL,'VK_BRUTTO','PRICE',First); AddSet(SQL,'MATERIALPREIS','MAT',First); AddSet(SQL,'EK_PREIS','EK',First);
      AddSet(SQL,'STANDARD_ETIKETT','ETIKETT',First); AddSet(SQL,'EINHEIT','EINHEIT',First);
      AddSet(SQL,'RZ_BRENNWERTKCAL','RZ_KCAL',First); AddSet(SQL,'RZ_BRENNWERTKJOULE','RZ_KJOULE',First);
      AddSet(SQL,'RZ_EIWEISS','RZ_EIWEISS',First); AddSet(SQL,'RZ_KOHLENHYDRATE','RZ_KOHLENHYDRATE',First);
      AddSet(SQL,'RZ_ZUCKER','RZ_ZUCKER',First); AddSet(SQL,'RZ_FETT','RZ_FETT',First);
      AddSet(SQL,'RZ_FETTGESAETTIGT','RZ_FETTGES',First); AddSet(SQL,'RZ_SALZ','RZ_SALZ',First); AddSet(SQL,'RZ_BALLAST','RZ_BALLAST',First);
      SQL := SQL + ' where ID = :ID';
    end
    else
    begin
      Q.Connection := FB;
      Q.SQL.Text := 'select coalesce(max(ID), 0) + 1 as NEWID from ARTIKEL';
      Q.Open;
      ID := Q.FieldByName('NEWID').AsInteger;
      Q.Close;
      Fields := 'ID'; Values := ':ID'; First := False;
      AddInsertField(Fields,Values,'NL_KEY','NLKEY',First);
      AddInsertField(Fields,Values,'ELENO','ELENO',First);
      AddInsertField(Fields,Values,'NUMMER','NUMMER',First);
      AddInsertField(Fields,Values,'BEZEICHNUNG','BEZ',First);
      AddInsertField(Fields,Values,'BEZEICHNUNG2','BEZ2',First);
      AddInsertField(Fields,Values,'MHD','MHD',First);
      AddInsertField(Fields,Values,'LAGERTEMPERATUR','TEMP',First);
      AddInsertField(Fields,Values,'WG','WG',First);
      AddInsertField(Fields,Values,'MWST_1','MWST',First);
      AddInsertField(Fields,Values,'EAN','EAN',First);
      AddInsertField(Fields,Values,'ZUTATENTEXT','ZUTATEN',First);
      AddInsertField(Fields,Values,'TARANR','TARA',First);
      AddInsertField(Fields,Values,'NENNGEWICHT','NENNGEWICHT',First);
      AddInsertField(Fields,Values,'VK_BRUTTO','PRICE',First);
      AddInsertField(Fields,Values,'MATERIALPREIS','MAT',First);
      AddInsertField(Fields,Values,'EK_PREIS','EK',First);
      AddInsertField(Fields,Values,'STANDARD_ETIKETT','ETIKETT',First);
      AddInsertField(Fields,Values,'EINHEIT','EINHEIT',First);
      AddInsertField(Fields,Values,'RZ_BRENNWERTKCAL','RZ_KCAL',First);
      AddInsertField(Fields,Values,'RZ_BRENNWERTKJOULE','RZ_KJOULE',First);
      AddInsertField(Fields,Values,'RZ_EIWEISS','RZ_EIWEISS',First);
      AddInsertField(Fields,Values,'RZ_KOHLENHYDRATE','RZ_KOHLENHYDRATE',First);
      AddInsertField(Fields,Values,'RZ_ZUCKER','RZ_ZUCKER',First);
      AddInsertField(Fields,Values,'RZ_FETT','RZ_FETT',First);
      AddInsertField(Fields,Values,'RZ_FETTGESAETTIGT','RZ_FETTGES',First);
      AddInsertField(Fields,Values,'RZ_SALZ','RZ_SALZ',First);
      AddInsertField(Fields,Values,'RZ_BALLAST','RZ_BALLAST',First);
      SQL := 'insert into ARTIKEL (' + Fields + ') values (' + Values + ')';
    end;

    Q.Connection := FB;
    Q.SQL.Text := SQL;
    Q.ParamByName('ID').AsInteger := ID;
    if Q.Params.FindParam('ELENO') <> nil then
      Q.ParamByName('ELENO').AsInteger := Number;
    if Q.Params.FindParam('NLKEY') <> nil then Q.ParamByName('NLKEY').AsInteger := SCOConfig.NLKey;
    SetParam(Q,'NUMMER',O.GetValue('nummer'),'int');
    SetParam(Q,'BEZ',O.GetValue('bezeichnung'),'string'); SetParam(Q,'BEZ2',O.GetValue('bezeichnung2'),'string');
    SetParam(Q,'MHD',O.GetValue('mhd'),'int'); SetParam(Q,'TEMP',O.GetValue('temperatur'),'int');
    SetParam(Q,'WG',O.GetValue('wg'),'int'); SetParam(Q,'MWST',O.GetValue('mwst'),'int'); SetParam(Q,'EAN',O.GetValue('ean'),'string');
    SetParam(Q,'ZUTATEN',O.GetValue('zutatentext'),'string'); SetParam(Q,'TARA',O.GetValue('taranr'),'int'); SetParam(Q,'NENNGEWICHT',O.GetValue('nenngewicht'),'float');
    SetParam(Q,'PRICE',O.GetValue('price'),'float'); SetParam(Q,'MAT',O.GetValue('material'),'float'); SetParam(Q,'EK',O.GetValue('ek'),'float');
    SetParam(Q,'ETIKETT',O.GetValue('standardEtikett'),'int'); SetParam(Q,'EINHEIT',O.GetValue('einheit'),'int');
    SetParam(Q,'RZ_KCAL',O.GetValue('rz_kcal'),'float'); SetParam(Q,'RZ_KJOULE',O.GetValue('rz_kjoule'),'float');
    SetParam(Q,'RZ_EIWEISS',O.GetValue('rz_eiweiss'),'float'); SetParam(Q,'RZ_KOHLENHYDRATE',O.GetValue('rz_kohlenhydrate'),'float');
    SetParam(Q,'RZ_ZUCKER',O.GetValue('rz_zucker'),'float'); SetParam(Q,'RZ_FETT',O.GetValue('rz_fett'),'float');
    SetParam(Q,'RZ_FETTGES',O.GetValue('rz_fettges'),'float'); SetParam(Q,'RZ_SALZ',O.GetValue('rz_salz'),'float'); SetParam(Q,'RZ_BALLAST',O.GetValue('rz_ballast'),'float');
    Q.ExecSQL;
    Result := '{"ok":true,"id":' + IntToStr(ID) + ',"message":"Artikel gespeichert."}';
  except
    on E: Exception do begin LogError('ADMIN ARTICLE SAVE ERROR: '+E.Message); Result := '{"ok":false,"message":"'+JS(E.Message)+'"}'; end;
  end;
  Q.Free; O.Free;
end;

function AdminArticleDeleteJson(ID: Integer): string;
var Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text := 'delete from ARTIKEL where ID = :ID';
    Q.ParamByName('ID').AsInteger := ID;
    Q.ExecSQL;
    Result := '{"ok":true,"message":"Artikel geloescht."}';
  except on E: Exception do Result := '{"ok":false,"message":"'+JS(E.Message)+'"}'; end;
  Q.Free;
end;

function AdminArticleImageSaveJson(ID: Integer; const Body: string): string;
var
  O: TJSONObject;
  ImageText, Encoded: string;
  CommaPos: Integer;
  Bytes: TBytes;
  Stream: TBytesStream;
  Q: TFDQuery;
begin
  if ID <= 0 then Exit('{"ok":false,"message":"Artikel erst speichern, dann Bild hochladen."}');
  O := TJSONObject.ParseJSONValue(Body) as TJSONObject;
  if O = nil then Exit('{"ok":false,"message":"Ungueltige Bilddaten."}');
  Q := TFDQuery.Create(nil);
  Stream := nil;
  try
    ImageText := O.GetValue<string>('image', '');
    CommaPos := Pos(',', ImageText);
    if CommaPos > 0 then Encoded := Copy(ImageText, CommaPos + 1, MaxInt) else Encoded := ImageText;
    if Trim(Encoded) = '' then Exit('{"ok":false,"message":"Keine Bilddaten empfangen."}');
    Bytes := TNetEncoding.Base64.DecodeStringToBytes(Encoded);
    Stream := TBytesStream.Create(Bytes);
    Stream.Position := 0;
    Q.Connection := FB;
    Q.SQL.Text := 'update PRODUKT_BILDER set BILD = :BILD where ID = :ID';
    Q.ParamByName('ID').AsInteger := ID;
    Q.ParamByName('BILD').LoadFromStream(Stream, ftBlob);
    Q.ExecSQL;
    if Q.RowsAffected = 0 then
    begin
      Stream.Position := 0;
      Q.SQL.Text := 'insert into PRODUKT_BILDER (ID, LFDNO, BILD) values (:ID, 1, :BILD)';
      Q.ParamByName('ID').AsInteger := ID;
      Q.ParamByName('BILD').LoadFromStream(Stream, ftBlob);
      Q.ExecSQL;
    end;
    Result := '{"ok":true,"message":"Bild gespeichert."}';
  except
    on E: Exception do begin LogError('ADMIN ARTICLE IMAGE SAVE ERROR: ' + E.Message); Result := '{"ok":false,"message":"' + JS(E.Message) + '"}'; end;
  end;
  Stream.Free; Q.Free; O.Free;
end;

function AdminArticleDuplicateJson(ID: Integer): string;
var
  Q, Meta: TFDQuery;
  NewID, NewNumber: Integer;
  Fields, SelectFields, FieldName: string;
begin
  Q := TFDQuery.Create(nil);
  Meta := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Meta.Connection := FB;

    Q.SQL.Text := 'select coalesce(max(ID), 0) + 1 as NEWID from ARTIKEL';
    Q.Open;
    NewID := Q.FieldByName('NEWID').AsInteger;
    Q.Close;

    Q.SQL.Text := 'select coalesce(max(NUMMER), 0) + 1 as NEWNUMBER from ARTIKEL where NL_KEY = :NLKEY';
    Q.ParamByName('NLKEY').AsInteger := SCOConfig.NLKey;
    Q.Open;
    NewNumber := Q.FieldByName('NEWNUMBER').AsInteger;
    Q.Close;

    Fields := '';
    SelectFields := '';
    Meta.SQL.Text :=
      'select trim(RDB$FIELD_NAME) as FIELD_NAME from RDB$RELATION_FIELDS ' +
      'where RDB$RELATION_NAME = ''ARTIKEL'' order by RDB$FIELD_POSITION';
    Meta.Open;
    while not Meta.Eof do
    begin
      FieldName := Trim(Meta.FieldByName('FIELD_NAME').AsString);
      if Fields <> '' then
      begin
        Fields := Fields + ',';
        SelectFields := SelectFields + ',';
      end;
      Fields := Fields + FieldName;
      if SameText(FieldName, 'ID') then
        SelectFields := SelectFields + ':NEWID'
      else if SameText(FieldName, 'NUMMER') or SameText(FieldName, 'ELENO') then
        SelectFields := SelectFields + ':NEWNUMBER'
      else if SameText(FieldName, 'BEZEICHNUNG') then
        SelectFields := SelectFields + 'BEZEICHNUNG || '' Kopie'''
      else if SameText(FieldName, 'EAN') then
        SelectFields := SelectFields + 'NULL'
      else
        SelectFields := SelectFields + FieldName;
      Meta.Next;
    end;

    Q.SQL.Text := 'insert into ARTIKEL (' + Fields + ') select ' +
      SelectFields + ' from ARTIKEL where ID = :SOURCEID';
    Q.ParamByName('NEWID').AsInteger := NewID;
    Q.ParamByName('NEWNUMBER').AsInteger := NewNumber;
    Q.ParamByName('SOURCEID').AsInteger := ID;
    Q.ExecSQL;
    if Q.RowsAffected = 0 then
      raise Exception.Create('Quellartikel nicht gefunden.');

    try
      Q.SQL.Text :=
        'insert into PRODUKT_BILDER (ID, LFDNO, BILD) ' +
        'select :NEWID, LFDNO, BILD from PRODUKT_BILDER where ID = :SOURCEID';
      Q.ParamByName('NEWID').AsInteger := NewID;
      Q.ParamByName('SOURCEID').AsInteger := ID;
      Q.ExecSQL;
    except
      on E: Exception do
        LogError('ADMIN ARTICLE DUPLICATE IMAGE: ' + E.Message);
    end;

    Result := '{"ok":true,"id":' + IntToStr(NewID) +
      ',"number":' + IntToStr(NewNumber) +
      ',"message":"Artikel dupliziert. Neue PLU: ' + IntToStr(NewNumber) + '."}';
  except
    on E: Exception do
    begin
      LogError('ADMIN ARTICLE DUPLICATE ERROR: ' + E.Message);
      Result := '{"ok":false,"message":"' + JS(E.Message) + '"}';
    end;
  end;
  Meta.Free;
  Q.Free;
end;

function AdminArticleNextNumberJson: string;
var Q: TFDQuery; N: Integer;
begin
  Q := TFDQuery.Create(nil);
  try
    SCOConfig.Load;
    Q.Connection := FB;
    Q.SQL.Text := 'select coalesce(max(NUMMER), 0) + 1 as N from ARTIKEL where NL_KEY = :NLKEY';
    Q.ParamByName('NLKEY').AsInteger := SCOConfig.NLKey;
    Q.Open;
    N := Q.FieldByName('N').AsInteger;
    Result := '{"ok":true,"number":' + IntToStr(N) + '}';
  except on E: Exception do Result := '{"ok":false,"message":"' + JS(E.Message) + '"}'; end;
  Q.Free;
end;

function AdminGroupSaveJson(const Body: string): string;
var O: TJSONObject; Q: TFDQuery; Number: Integer; Name: string;
begin
  O := TJSONObject.ParseJSONValue(Body) as TJSONObject;
  if O = nil then Exit('{"ok":false,"message":"UngÃ¼ltige Warengruppe."}');
  Q := TFDQuery.Create(nil);
  try
    SCOConfig.Load;
    Number := StrToIntDef(O.GetValue<string>('number', '0'), 0);
    Name := Trim(O.GetValue<string>('name', ''));
    if Name = '' then raise Exception.Create('Bitte eine Bezeichnung eingeben.');
    Q.Connection := FB;
    if Number <= 0 then
    begin
      Q.SQL.Text := 'select coalesce(max(NUMMER), 0) + 1 as N from GRUPPEN where NL_KEY = :NLKEY';
      Q.ParamByName('NLKEY').AsInteger := SCOConfig.NLKey; Q.Open;
      Number := Q.FieldByName('N').AsInteger; Q.Close;
      Q.SQL.Text := 'insert into GRUPPEN (ID, NL_KEY, HGRUPPE, NUMMER, BEZEICHNUNG) ' +
        'values ((select coalesce(max(ID),0)+1 from GRUPPEN), :NLKEY, 1, :NUMMER, :BEZ)';
    end
    else
    begin
      Q.SQL.Text := 'update GRUPPEN set BEZEICHNUNG = :BEZ where NL_KEY = :NLKEY and NUMMER = :NUMMER';
    end;
    Q.ParamByName('NLKEY').AsInteger := SCOConfig.NLKey;
    Q.ParamByName('NUMMER').AsInteger := Number;
    Q.ParamByName('BEZ').AsString := Name;
    Q.ExecSQL;
    Result := '{"ok":true,"number":' + IntToStr(Number) + ',"message":"Warengruppe gespeichert."}';
  except on E: Exception do begin LogError('ADMIN GROUP SAVE ERROR: ' + E.Message); Result := '{"ok":false,"message":"' + JS(E.Message) + '"}'; end; end;
  Q.Free; O.Free;
end;

function AdminGroupDeleteJson(Number: Integer): string;
var Q: TFDQuery; Used: Integer;
begin
  Q := TFDQuery.Create(nil);
  try
    SCOConfig.Load; Q.Connection := FB;
    Q.SQL.Text := 'select count(*) as C from ARTIKEL where NL_KEY = :NLKEY and WG = :WG';
    Q.ParamByName('NLKEY').AsInteger := SCOConfig.NLKey; Q.ParamByName('WG').AsInteger := Number; Q.Open;
    Used := Q.FieldByName('C').AsInteger; Q.Close;
    if Used > 0 then raise Exception.Create('Warengruppe ist noch ' + IntToStr(Used) + ' Artikel(n) zugeordnet.');
    Q.SQL.Text := 'delete from GRUPPEN where NL_KEY = :NLKEY and NUMMER = :WG';
    Q.ParamByName('NLKEY').AsInteger := SCOConfig.NLKey; Q.ParamByName('WG').AsInteger := Number; Q.ExecSQL;
    Result := '{"ok":true,"message":"Warengruppe gelÃ¶scht."}';
  except on E: Exception do begin LogError('ADMIN GROUP DELETE ERROR: ' + E.Message); Result := '{"ok":false,"message":"' + JS(E.Message) + '"}'; end; end;
  Q.Free;
end;
end.





