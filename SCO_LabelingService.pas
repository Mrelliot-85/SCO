unit SCO_LabelingService;
interface
uses
  System.SysUtils;
function LabelingGroupsJson: string;
function LabelingProductsJson(WG: Integer): string;
function LabelingSearchJson(const SearchText: string): string;
function LabelingTarasJson: string;
function LabelingScanJson(const EAN: string): string;
function LabelingReadWeightJson: string;
function LabelPrinterTestJson(const Host: string; Port: Integer; const WindowsPrinter: string): string;
function LabelingPrintJson(PLU: Integer; Weight: Double; Tara: Double; Qty: Integer;
  const MHD, TemplateName: string): string;
function LabelingWriteRfidJson(PLU: Integer; Weight: Double): string;
function LabelingSaveRfidJson(PLU: Integer; const Tag, MHD, Source: string; Weight: Double; Tara: Double; Price: Double; Overwrite: Boolean = False): string;
function LabelingInvalidateRfidJson(const Tag: string): string;
function LabelingProtocolJson(Limit: Integer): string;
function LabelingProtocolDeleteJson(ID: Integer): string;
function LabelingProtocolStatusJson(ID, Status: Integer): string;
implementation
uses
  FireDAC.Comp.Client,
  System.Classes, System.Types, System.StrUtils, System.Math, System.SyncObjs,
  Winapi.Windows, Winapi.WinSpool,
  IdTCPClient, IdGlobal,
  SCO_DB,
  SCO_CONFIG,
  SCO_ScaleService,
  SCO_LabelDesignerService,
  SCO_Logger;

var
  LabelingDBLock: TCriticalSection;

function GetArtikelVKBrutto(ArtikelID: Integer): Double; forward;
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
function PriceJson(Value: Double): string;
begin
  Result := StringReplace(FormatFloat('0.00', Value), ',', '.', []);
end;

function LogNumber(Value: Double; const Mask: string): string;
begin
  Result := StringReplace(FormatFloat(Mask, Value), ',', '.', []);
end;
function DigitsOnly(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    if S[I] in ['0'..'9'] then
      Result := Result + S[I];
end;
function EAN13CheckDigit(const S12: string): Integer;
var
  I, Summe, Z: Integer;
begin
  Summe := 0;
  for I := 1 to 12 do
  begin
    Z := Ord(S12[I]) - Ord('0');
    if (I mod 2) = 0 then
      Summe := Summe + (Z * 3)
    else
      Summe := Summe + Z;
  end;
  Result := (10 - (Summe mod 10)) mod 10;
end;
function FieldFloatDef(Q: TFDQuery; const FieldName: string; DefaultValue: Double): Double;
begin
  Result := DefaultValue;
  if Q.FindField(FieldName) = nil then
    Exit;
  if Q.FieldByName(FieldName).IsNull then
    Exit;
  Result := Q.FieldByName(FieldName).AsFloat;
end;

function FieldStrDef(Q: TFDQuery; const FieldName, DefaultValue: string): string;
begin
  Result := DefaultValue;
  if Q.FindField(FieldName) = nil then
    Exit;
  if Q.FieldByName(FieldName).IsNull then
    Exit;
  Result := Q.FieldByName(FieldName).AsString;
end;

function FieldDateInputDef(Q: TFDQuery; const FieldName: string): string;
begin
  Result := '';
  if Q.FindField(FieldName) = nil then
    Exit;
  if Q.FieldByName(FieldName).IsNull then
    Exit;
  try
    Result := FormatDateTime('yyyy-mm-dd', Q.FieldByName(FieldName).AsDateTime);
  except
    Result := '';
  end;
end;

function SafeJsonNumber(const S: string; DefaultValue: string): string;
begin
  Result := Trim(S);
  if Result = '' then
    Result := DefaultValue;
end;

function ProductJsonFromQuery(Q: TFDQuery; const SourceText: string;
  Weight, EanPrice: Double): string;
var
  UnitPrice: Double;
  NennGewicht: Double;
  MHDText: string;
begin
  UnitPrice := FieldFloatDef(Q, 'PREIS', 0);
  if UnitPrice <= 0 then
    UnitPrice := FieldFloatDef(Q, 'VK_BRUTTO', 0);

  NennGewicht := FieldFloatDef(Q, 'NENNGEWICHT', 0);
  MHDText := FieldDateInputDef(Q, 'MHD');

  Result :=
    '{' +
    '"ok":true,' +
    '"source":"' + JS(SourceText) + '",' +
    '"plu":' + SafeJsonNumber(Q.FieldByName('ELENO').AsString, '0') + ',' +
    '"id":' + SafeJsonNumber(Q.FieldByName('ID').AsString, '0') + ',' +
    '"name":"' + JS(Q.FieldByName('BEZEICHNUNG').AsString) + '",' +
    '"name2":"' + JS(FieldStrDef(Q, 'BEZEICHNUNG2', '')) + '",' +
    '"unit":"' + JS(FieldStrDef(Q, 'ME_BEZ', 'Stck')) + '",' +
    '"wg":' + SafeJsonNumber(FieldStrDef(Q, 'WG', '0'), '0') + ',' +
    '"group":"' + JS(FieldStrDef(Q, 'WG_BEZ', '')) + '",' +
    '"price":' + PriceJson(UnitPrice) + ',' +
    '"ep":' + PriceJson(UnitPrice) + ',' +
    '"weight":' + FloatJson(Weight) + ',' +
    '"nenngewicht":' + FloatJson(NennGewicht) + ',' +
    '"taranr":' + SafeJsonNumber(FieldStrDef(Q, 'TARANR', '0'), '0') + ',' +
    '"eanprice":' + PriceJson(EanPrice) + ',' +
    '"totalPrice":' + PriceJson(EanPrice) + ',' +
    '"mhd":"' + JS(MHDText) + '",' +
    '"mhdDays":' + SafeJsonNumber(FieldStrDef(Q, 'MHD', '0'), '0') + ',' +
    '"labelNumber":' + SafeJsonNumber(FieldStrDef(Q, 'STANDARD_ETIKETT', '0'), '0') + ',' +
    '"ean":"' + JS(FieldStrDef(Q, 'EAN', '')) + '",' +
    '"ingredients":"' + JS(FieldStrDef(Q, 'ZUTATENTEXT', '')) + '",' +
    '"image":"/api/productimage?id=' + SafeJsonNumber(FieldStrDef(Q, 'ID', '0'), '0') + '"' +
    '}';
end;
function OpenProductByDirectEAN(Q: TFDQuery; const EAN: string): Boolean;
begin
  Q.Close;
  Q.SQL.Text :=
    'select first 1 ' +
    '  cast(NUMMER as varchar(20)) as ELENO, VK_BRUTTO as PREIS, VK_BRUTTO, NENNGEWICHT, MHD, TARANR, STANDARD_ETIKETT, EAN, ZUTATENTEXT, ' +
    '  ID, BEZEICHNUNG, BEZEICHNUNG2, ME_BEZ, WG, WG_BEZ ' +
    'from VARTIKEL ' +
    'where trim(coalesce(EAN, '''')) = :EAN';
  Q.ParamByName('EAN').AsString := EAN;
  Q.Open;
  Result := not Q.IsEmpty;
end;
function OpenProductByArticleNo(Q: TFDQuery; ArtikelNo: Integer): Boolean;
var
  SArtikel, SArtikel5: string;
begin
  SArtikel := IntToStr(ArtikelNo);
  SArtikel5 := Format('%.5d', [ArtikelNo]);
  Q.Close;
  Q.SQL.Text :=
    'select first 1 ' +
    '  cast(NUMMER as varchar(20)) as ELENO, VK_BRUTTO as PREIS, VK_BRUTTO, NENNGEWICHT, MHD, TARANR, STANDARD_ETIKETT, EAN, ZUTATENTEXT, ' +
    '  ID, BEZEICHNUNG, BEZEICHNUNG2, ME_BEZ, WG, WG_BEZ ' +
    'from VARTIKEL ' +
    'where trim(cast(ELENO as varchar(20))) = :ARTIKEL ' +
    '   or trim(cast(ELENO as varchar(20))) = :ARTIKEL5 ' +
    '   or trim(cast(NUMMER as varchar(20))) = :ARTIKEL';
  Q.ParamByName('ARTIKEL').AsString := SArtikel;
  Q.ParamByName('ARTIKEL5').AsString := SArtikel5;
  Q.Open;
  Result := not Q.IsEmpty;
end;
function LabelingGroupsJson: string;
begin
  Result := GetGroupsJson;
end;
function LabelingProductsJson(WG: Integer): string;
var
  Q: TFDQuery;
  First: Boolean;
begin
  SCOConfig.Load;

  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'select first 120 ' +
      '  cast(NUMMER as varchar(20)) as ELENO, VK_BRUTTO as PREIS, VK_BRUTTO, NENNGEWICHT, MHD, TARANR, STANDARD_ETIKETT, EAN, ID, BEZEICHNUNG, BEZEICHNUNG2, ' +
      '  ME_BEZ, WG, WG_BEZ ' +
      'from VARTIKEL ' +
      'where (:WG = 0 or WG = :WG) ' +
      'order by BEZEICHNUNG';
    Q.ParamByName('WG').AsInteger := WG;
    Q.Open;

    Result := '[';
    First := True;
    while not Q.Eof do
    begin
      if not First then
        Result := Result + ',';

      Result := Result +
        '{' +
        '"plu":' + SafeJsonNumber(FieldStrDef(Q, 'ELENO', '0'), '0') + ',' +
        '"id":' + SafeJsonNumber(FieldStrDef(Q, 'ID', '0'), '0') + ',' +
        '"name":"' + JS(Q.FieldByName('BEZEICHNUNG').AsString) + '",' +
        '"name2":"' + JS(FieldStrDef(Q, 'BEZEICHNUNG2', '')) + '",' +
        '"unit":"' + JS(FieldStrDef(Q, 'ME_BEZ', 'Stck')) + '",' +
        '"wg":' + SafeJsonNumber(FieldStrDef(Q, 'WG', '0'), '0') + ',' +
        '"group":"' + JS(FieldStrDef(Q, 'WG_BEZ', '')) + '",' +
        '"price":' + PriceJson(FieldFloatDef(Q, 'PREIS', 0)) + ',' +
        '"ep":' + PriceJson(FieldFloatDef(Q, 'PREIS', 0)) + ',' +
        '"nenngewicht":' + FloatJson(FieldFloatDef(Q, 'NENNGEWICHT', 0)) + ',' +
        '"taranr":' + SafeJsonNumber(FieldStrDef(Q, 'TARANR', '0'), '0') + ',' +
        '"mhd":"",' +
        '"mhdDays":' + SafeJsonNumber(FieldStrDef(Q, 'MHD', '0'), '0') + ',' +
        '"labelNumber":' + SafeJsonNumber(FieldStrDef(Q, 'STANDARD_ETIKETT', '0'), '0') + ',' +
        '"ean":"' + JS(FieldStrDef(Q, 'EAN', '')) + '",' +
        '"ingredients":"",' +
        '"image":"/api/productimage?id=' + SafeJsonNumber(FieldStrDef(Q, 'ID', '0'), '0') + '"' +
        '}';

      First := False;
      Q.Next;
    end;
    Result := Result + ']';
  except
    on E: Exception do
    begin
      LogError('LABEL PRODUCTS ERROR: ' + E.Message);
      Result := '[]';
    end;
  end;
  Q.Free;
end;

function TryParseDateParam(const S: string; var D: TDateTime): Boolean;
var
  Y, M, DayNo: Word;
begin
  Result := False;
  D := 0;

  if Trim(S) = '' then
    Exit;

  try
    D := StrToDate(S);
    Result := True;
    Exit;
  except
  end;

  if (Length(S) = 10) and (S[5] = '-') and (S[8] = '-') then
  begin
    try
      Y := StrToInt(Copy(S, 1, 4));
      M := StrToInt(Copy(S, 6, 2));
      DayNo := StrToInt(Copy(S, 9, 2));
      D := EncodeDate(Y, M, DayNo);
      Result := True;
    except
      Result := False;
    end;
  end;
end;

function GenerateLabelTag13: string;
var
  V: Int64;
  Base12: string;
begin
  V := Trunc((Now - EncodeDate(2020, 1, 1)) * 86400000);
  Base12 := '2' + Format('%.11d', [V mod 100000000000]);
  Result := Base12 + IntToStr(EAN13CheckDigit(Base12));
end;

procedure SaveNormalLabelInfo(PLU: Integer; Weight, Tara: Double; const MHD, LabelTag: string);
var
  Q: TFDQuery;
  ParsedMHD: TDateTime;
  Tag: string;
  SavePrice: Double;
begin
  if PLU <= 0 then
    Exit;
  Tag := Trim(LabelTag);
  if Tag = '' then Tag := GenerateLabelTag13;
  SavePrice := GetArtikelVKBrutto(PLU);
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'insert into TAGINFO ' +
      '(TAG, MHD, TYP, GEWICHT, TARA, PREIS, NUMMER, STATUS, CREATEDATE, CHANGEDATE, CHARGE) ' +
      'values ' +
      '(:TAG, :MHD, 2, :GEWICHT, :TARA, :PREIS, :NUMMER, 0, CURRENT_TIMESTAMP, null, :CHARGE)';
    Q.ParamByName('TAG').AsString := Tag;
    if Trim(MHD) = '' then
      Q.ParamByName('MHD').Clear
    else if TryParseDateParam(MHD, ParsedMHD) then
      Q.ParamByName('MHD').AsDate := ParsedMHD
    else
      Q.ParamByName('MHD').Clear;
    Q.ParamByName('GEWICHT').AsFloat := Weight;
    Q.ParamByName('TARA').AsFloat := Tara;
    Q.ParamByName('PREIS').AsFloat := SavePrice;
    Q.ParamByName('NUMMER').AsInteger := PLU;
    Q.ParamByName('CHARGE').AsString := '';
    Q.ExecSQL;
    LogTransaction('LABEL TAGINFO OK TAG=' + Tag + ' PLU=' + IntToStr(PLU) + ' TARA=' + FloatToStr(Tara));
    LogWeighing('TAGINFO_EAN PLU=' + IntToStr(PLU) + ' TAG=' + Tag + ' BRUTTO=' + LogNumber(Weight + Tara, '0.000') + 'kg TARA=' + LogNumber(Tara, '0.000') + 'kg NETTO=' + LogNumber(Weight, '0.000') + 'kg PREIS=' + LogNumber(SavePrice, '0.00') + ' MHD=' + MHD);
  except
    on E: Exception do
      LogError('LABEL TAGINFO ERROR: ' + E.Message);
  end;
  Q.Free;
end;

function LabelingSaveRfidJsonInternal(PLU: Integer; const Tag, MHD, Source: string;
  Weight: Double; Tara: Double; Price: Double; Overwrite: Boolean): string;
var
  Q: TFDQuery;
  CleanTag, UnitName: string;
  Typ, ExistingID: Integer;
  NeedLen: Integer;
  ParsedMHD: TDateTime;
  SavePrice, StoreWeight: Double;
begin
  SCOConfig.Load;
  NeedLen := SCOConfig.LabelingTagLength;
  CleanTag := Trim(Tag);
  ExistingID := 0;

  LogWeighing('RFID_SAVE_START PLU=' + IntToStr(PLU) + ' TAG=' + CleanTag + ' SOURCE=' + Source + ' BRUTTO=' + LogNumber(Weight + Tara, '0.000') + 'kg TARA=' + LogNumber(Tara, '0.000') + 'kg NETTO=' + LogNumber(Weight, '0.000') + 'kg CLIENTPRICE=' + LogNumber(Price, '0.00') + ' MHD=' + MHD);

  LogTransaction(
    'RFID SAVE START PLU=' + IntToStr(PLU) +
    ' TAG=' + CleanTag +
    ' TAGLEN=' + IntToStr(Length(CleanTag)) +
    ' NEEDLEN=' + IntToStr(NeedLen) +
    ' SOURCE=' + Source +
    ' WEIGHT=' + FloatToStr(Weight) +
    ' TARA=' + FloatToStr(Tara) +
    ' CLIENTPRICE=' + FloatToStr(Price)
  );

  if PLU <= 0 then
  begin
    Result := '{"ok":false,"message":"Kein Artikel ausgewaehlt."}';
    Exit;
  end;

  if CleanTag = '' then
  begin
    LogError('RFID SAVE ABORT: empty tag');
    Result := '{"ok":false,"message":"Kein RFID-Tag gelesen."}';
    Exit;
  end;

  if (NeedLen > 0) and (Length(CleanTag) <> NeedLen) then
  begin
    LogError('RFID SAVE ABORT: tag length ' + IntToStr(Length(CleanTag)) + ' expected ' + IntToStr(NeedLen));
    Result := '{"ok":false,"message":"RFID-Tag hat falsche Laenge: ' + IntToStr(Length(CleanTag)) + ' / ' + IntToStr(NeedLen) + '."}';
    Exit;
  end;

  Typ := 1;

  Q := TFDQuery.Create(nil);
  try
    try
      Q.Connection := FB;

      Q.SQL.Text :=
        'select first 1 ID, STATUS from TAGINFO where TAG = :TAG';
      Q.ParamByName('TAG').AsString := CleanTag;
      Q.Open;

      if not Q.IsEmpty then
      begin
        ExistingID := Q.FieldByName('ID').AsInteger;
        if not Overwrite then
        begin
          LogError('RFID SAVE DUPLICATE TAG=' + CleanTag + ' ID=' + Trim(Q.FieldByName('ID').AsString));
          Result :=
            '{"ok":false,' +
            '"duplicate":true,' +
            '"canOverwrite":true,' +
            '"message":"RFID-Tag ist bereits vorhanden und wurde nicht erneut gespeichert.",' +
            '"id":' + SafeJsonNumber(FieldStrDef(Q, 'ID', '0'), '0') + ',' +
            '"status":' + Trim(Q.FieldByName('STATUS').AsString) + ',' +
            '"tag":"' + JS(CleanTag) + '"}';
          Exit;
        end;
        LogTransaction('RFID SAVE OVERWRITE REQUEST TAG=' + CleanTag + ' ID=' + IntToStr(ExistingID));
      end;

      Q.Close;

      SavePrice := Price;
      if SavePrice > 0 then
        LogTransaction('RFID SAVE PRICE EAN/CLIENT PLU=' + IntToStr(PLU) + ' PRICE=' + FloatToStr(SavePrice));

      if SavePrice <= 0 then
      begin
        SavePrice := GetArtikelVKBrutto(PLU);
        LogTransaction('RFID SAVE PRICE VK_BRUTTO PLU=' + IntToStr(PLU) + ' PRICE=' + FloatToStr(SavePrice));
      end;

      if SavePrice <= 0 then
      begin
        Q.SQL.Text :=
          'select first 1 VK_BRUTTO from VARTIKEL ' +
          'where trim(cast(NUMMER as varchar(20))) = :PLU or trim(cast(NUMMER as varchar(20))) = :PLU5 or trim(cast(ELENO as varchar(20))) = :PLU';
        Q.ParamByName('PLU').AsString := IntToStr(PLU);
        Q.ParamByName('PLU5').AsString := Format('%.5d', [PLU]);
        Q.Open;

        if not Q.IsEmpty then
          SavePrice := FieldFloatDef(Q, 'VK_BRUTTO', 0);

        Q.Close;
        LogTransaction('RFID SAVE PRICE VK_BRUTTO PLU=' + IntToStr(PLU) + ' PRICE=' + FloatToStr(SavePrice));
      end;

      if SavePrice <= 0 then
      begin
        SavePrice := Price;
        LogTransaction('RFID SAVE PRICE CLIENT FALLBACK PLU=' + IntToStr(PLU) + ' PRICE=' + FloatToStr(SavePrice));
      end;

      UnitName := '';
      StoreWeight := Weight;
      Q.SQL.Text :=
        'select first 1 ME_BEZ from VARTIKEL ' +
        'where trim(cast(NUMMER as varchar(20))) = :PLU or trim(cast(NUMMER as varchar(20))) = :PLU5 or trim(cast(ELENO as varchar(20))) = :PLU';
      Q.ParamByName('PLU').AsString := IntToStr(PLU);
      Q.ParamByName('PLU5').AsString := Format('%.5d', [PLU]);
      Q.Open;
      if not Q.IsEmpty then
        UnitName := FieldStrDef(Q, 'ME_BEZ', '');
      Q.Close;
      if not SameText(Trim(UnitName), 'kg') then
      begin
        StoreWeight := 0;
        Tara := 0;
      end;

      if ExistingID > 0 then
        Q.SQL.Text :=
          'update TAGINFO set ' +
          'TAG = :TAG, MHD = :MHD, TYP = :TYP, GEWICHT = :GEWICHT, TARA = :TARA, ' +
          'PREIS = :PREIS, NUMMER = :NUMMER, STATUS = 0, CHANGEDATE = CURRENT_TIMESTAMP, CHARGE = :CHARGE ' +
          'where ID = :ID'
      else
        Q.SQL.Text :=
          'insert into TAGINFO ' +
          '(TAG, MHD, TYP, GEWICHT, TARA, PREIS, NUMMER, STATUS, CREATEDATE, CHANGEDATE, CHARGE) ' +
          'values ' +
          '(:TAG, :MHD, :TYP, :GEWICHT, :TARA, :PREIS, :NUMMER, 0, CURRENT_TIMESTAMP, null, :CHARGE)';

      Q.ParamByName('TAG').AsString := CleanTag;

      if Trim(MHD) = '' then
        Q.ParamByName('MHD').Clear
      else
      begin
        if TryParseDateParam(MHD, ParsedMHD) then
          Q.ParamByName('MHD').AsDate := ParsedMHD
        else
          Q.ParamByName('MHD').Clear;
      end;

      Q.ParamByName('TYP').AsInteger := Typ;
      Q.ParamByName('GEWICHT').AsFloat := StoreWeight;
      Q.ParamByName('TARA').AsFloat := Tara;
      Q.ParamByName('PREIS').AsFloat := SavePrice;
      Q.ParamByName('NUMMER').AsInteger := PLU;
      Q.ParamByName('CHARGE').AsString := '';
      if ExistingID > 0 then
        Q.ParamByName('ID').AsInteger := ExistingID;

      Q.ExecSQL;

      LogTransaction(
        IfThen(ExistingID > 0, 'RFID SAVE OVERWRITE OK PLU=', 'RFID SAVE OK PLU=') + IntToStr(PLU) +
        ' TAG=' + CleanTag +
        ' PRICE=' + FloatToStr(SavePrice) +
        ' UNIT=' + UnitName +
        ' STOREWEIGHT=' + FloatToStr(StoreWeight)
      );
      LogWeighing('RFID_SAVE_OK PLU=' + IntToStr(PLU) + ' TAG=' + CleanTag + ' TYP=' + IntToStr(Typ) + ' STATUS=0 BRUTTO=' + LogNumber(Weight + Tara, '0.000') + 'kg TARA=' + LogNumber(Tara, '0.000') + 'kg NETTO=' + LogNumber(Weight, '0.000') + 'kg STOREGEWICHT=' + LogNumber(StoreWeight, '0.000') + 'kg EINHEIT=' + UnitName + ' PREIS=' + LogNumber(SavePrice, '0.00') + ' MHD=' + MHD);

      Result :=
        '{"ok":true,' +
        '"message":"' + JS(IfThen(ExistingID > 0, 'RFID-Tag wurde ueberschrieben.', 'RFID-Tag wurde gespeichert.')) + '",' +
        '"tag":"' + JS(CleanTag) + '",' +
        '"plu":' + IntToStr(PLU) + '}';

    except
      on E: Exception do
      begin
        LogError('RFID SAVE ERROR: ' + E.Message);
        Result := '{"ok":false,"message":"' + JS(E.Message) + '"}';
      end;
    end;
  finally
    Q.Free;
  end;
end;


function LabelingSaveRfidJson(PLU: Integer; const Tag, MHD, Source: string;
  Weight: Double; Tara: Double; Price: Double; Overwrite: Boolean): string;
begin
  LabelingDBLock.Acquire;
  try
    Result := LabelingSaveRfidJsonInternal(PLU, Tag, MHD, Source, Weight, Tara, Price, Overwrite);
  finally
    LabelingDBLock.Release;
  end;
end;

function LabelingInvalidateRfidJsonInternal(const Tag: string): string;
var
  Q: TFDQuery;
  CleanTag: string;
  ID, OldStatus, PLU: Integer;
  NeedLen: Integer;
begin
  SCOConfig.Load;
  CleanTag := Trim(Tag);
  NeedLen := SCOConfig.LabelingTagLength;
  LogTransaction('RFID INVALIDATE START TAG=' + CleanTag + ' TAGLEN=' + IntToStr(Length(CleanTag)));

  if CleanTag = '' then
    Exit('{"ok":false,"message":"Kein RFID-Tag gelesen."}');

  if (NeedLen > 0) and (Length(CleanTag) <> NeedLen) then
    Exit('{"ok":false,"message":"RFID-Tag hat falsche Laenge: ' + IntToStr(Length(CleanTag)) + ' / ' + IntToStr(NeedLen) + '."}');

  Q := TFDQuery.Create(nil);
  try
    try
      Q.Connection := FB;
      Q.SQL.Text := 'select first 1 ID, NUMMER, STATUS from TAGINFO where TAG = :TAG order by CREATEDATE desc';
      Q.ParamByName('TAG').AsString := CleanTag;
      Q.Open;
      if Q.IsEmpty then
      begin
        LogTransaction('RFID INVALIDATE NOT FOUND TAG=' + CleanTag);
        Exit('{"ok":false,"message":"RFID-Tag wurde in TAGINFO nicht gefunden.","tag":"' + JS(CleanTag) + '"}');
      end;

      ID := Q.FieldByName('ID').AsInteger;
      PLU := StrToIntDef(Q.FieldByName('NUMMER').AsString, 0);
      OldStatus := StrToIntDef(Q.FieldByName('STATUS').AsString, 0);
      Q.Close;

      Q.SQL.Text := 'update TAGINFO set STATUS = 9, CHANGEDATE = CURRENT_TIMESTAMP where ID = :ID';
      Q.ParamByName('ID').AsInteger := ID;
      Q.ExecSQL;

      LogTransaction('RFID INVALIDATE OK ID=' + IntToStr(ID) + ' TAG=' + CleanTag + ' PLU=' + IntToStr(PLU) + ' OLDSTATUS=' + IntToStr(OldStatus));
      Result := '{"ok":true,"message":"RFID-Tag wurde entwertet.","tag":"' + JS(CleanTag) + '","id":' + IntToStr(ID) + ',"plu":' + IntToStr(PLU) + ',"oldStatus":' + IntToStr(OldStatus) + ',"status":9}';
    except
      on E: Exception do
      begin
        LogError('RFID INVALIDATE ERROR: ' + E.Message);
        Result := '{"ok":false,"message":"' + JS(E.Message) + '"}';
      end;
    end;
  finally
    Q.Free;
  end;
end;

function LabelingInvalidateRfidJson(const Tag: string): string;
begin
  LabelingDBLock.Acquire;
  try
    Result := LabelingInvalidateRfidJsonInternal(Tag);
  finally
    LabelingDBLock.Release;
  end;
end;
function LabelingTarasJson: string;
var
  Q: TFDQuery;
  First: Boolean;
begin
  SCOConfig.Load;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'select ID, NUMMER, BEZEICHNUNG, WERT, REIHENFOLGE ' +
      'from TARAS ' +
      'where (NL_KEY = :NLKEY or :NLKEY = 0) ' +
      'order by REIHENFOLGE, NUMMER';
    Q.ParamByName('NLKEY').AsInteger := SCOConfig.NLKey;
    Q.Open;
    Result := '[';
    First := True;
    while not Q.Eof do
    begin
      if not First then
        Result := Result + ',';
      Result := Result +
        '{' +
        '"id":' + SafeJsonNumber(Q.FieldByName('ID').AsString, '0') + ',' +
        '"nummer":' + SafeJsonNumber(FieldStrDef(Q, 'NUMMER', '0'), '0') + ',' +
        '"name":"' + JS(FieldStrDef(Q, 'BEZEICHNUNG', '')) + '",' +
        '"value":' + FloatJson(FieldFloatDef(Q, 'WERT', 0)) +
        '}';
      First := False;
      Q.Next;
    end;
    Result := Result + ']';
  except
    on E: Exception do
    begin
      LogError('LABEL TARAS ERROR: ' + E.Message);
      Result := '[]';
    end;
  end;
  Q.Free;
end;
function LabelingSearchJson(const SearchText: string): string;
var
  Q: TFDQuery;
  First: Boolean;
  S: string;
begin
  SCOConfig.Load;
  S := Trim(SearchText);
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'select first 80 ' +
      '  cast(NUMMER as varchar(20)) as ELENO, VK_BRUTTO as PREIS, VK_BRUTTO, NENNGEWICHT, MHD, TARANR, STANDARD_ETIKETT, EAN, ZUTATENTEXT, ID, BEZEICHNUNG, BEZEICHNUNG2, ' +
      '  ME_BEZ, WG, WG_BEZ ' +
      'from VARTIKEL ' +
      'where upper(BEZEICHNUNG) containing upper(:S) ' +
      '   or upper(coalesce(BEZEICHNUNG2, '''')) containing upper(:S) ' +
      '   or cast(ELENO as varchar(20)) containing :S ' +
      '   or cast(NUMMER as varchar(20)) containing :S ' +
      '   or coalesce(EAN, '''') containing :S ' +
      'order by BEZEICHNUNG';
    Q.ParamByName('S').Size := 100;
    Q.ParamByName('S').AsString := Copy(S, 1, 100);
    Q.Open;
    Result := '[';
    First := True;
    while not Q.Eof do
    begin
      if not First then
        Result := Result + ',';
      Result := Result +
        '{' +
        '"plu":' + SafeJsonNumber(FieldStrDef(Q, 'ELENO', '0'), '0') + ',' +
        '"id":' + SafeJsonNumber(FieldStrDef(Q, 'ID', '0'), '0') + ',' +
        '"name":"' + JS(Q.FieldByName('BEZEICHNUNG').AsString) + '",' +
        '"name2":"' + JS(Q.FieldByName('BEZEICHNUNG2').AsString) + '",' +
        '"unit":"' + JS(Q.FieldByName('ME_BEZ').AsString) + '",' +
        '"wg":' + Trim(Q.FieldByName('WG').AsString) + ',' +
        '"group":"' + JS(Q.FieldByName('WG_BEZ').AsString) + '",' +
        '"price":' + PriceJson(FieldFloatDef(Q, 'PREIS', 0)) + ',' +
        '"nenngewicht":' + FloatJson(FieldFloatDef(Q, 'NENNGEWICHT', 0)) + ',' +
        '"taranr":' + SafeJsonNumber(FieldStrDef(Q, 'TARANR', '0'), '0') + ',' +
        '"mhd":"",' +
        '"mhdDays":' + SafeJsonNumber(FieldStrDef(Q, 'MHD', '0'), '0') + ',' +
        '"labelNumber":' + SafeJsonNumber(FieldStrDef(Q, 'STANDARD_ETIKETT', '0'), '0') + ',' +
        '"ean":"' + JS(FieldStrDef(Q, 'EAN', '')) + '",' +
        '"ingredients":"' + JS(FieldStrDef(Q, 'ZUTATENTEXT', '')) + '",' +
        '"image":"/api/productimage?id=' + SafeJsonNumber(FieldStrDef(Q, 'ID', '0'), '0') + '"' +
        '}';
      First := False;
      Q.Next;
    end;
    Result := Result + ']';
  finally
    Q.Free;
  end;
end;
function GetArtikelVKBrutto(ArtikelID: Integer): Double;
var
  Q: TFDQuery;
begin
  Result := 0;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'select first 1 VK_BRUTTO ' +
      'from VARTIKEL ' +
      'where trim(cast(ELENO as varchar(20))) = :PLU ' +
      '   or trim(cast(ELENO as varchar(20))) = :PLU5 ' +
      '   or trim(cast(NUMMER as varchar(20))) = :PLU';
    Q.ParamByName('PLU').AsString := IntToStr(ArtikelID);
    Q.ParamByName('PLU5').AsString := Format('%.5d', [ArtikelID]);
    Q.Open;
    if not Q.IsEmpty then
      Result := FieldFloatDef(Q, 'VK_BRUTTO', 0);
  finally
    Q.Free;
  end;
end;

function LabelingScanJson(const EAN: string): string;
var
  Q: TFDQuery;
  Code, Prefix, ArtikelText, WertText: string;
  Kennzahl, ArtikelNo, CheckIst, CheckSoll: Integer;
  IstPreisEAN: Boolean;
  Wert: Integer;
  Weight, EanPrice, ArtikelPreis, CalcPrice: Double;
begin
  SCOConfig.Load;
  Code := DigitsOnly(EAN);

  LogTransaction(
    'LABEL SCAN EAN=' + Code +
    ' MOD10=' + BoolToStr(SCOConfig.CheckEANMod10, True)
  );

  if Code = '' then
  begin
    Result := '{"ok":false,"message":"Kein EAN-Code uebergeben."}';
    Exit;
  end;

  Q := TFDQuery.Create(nil);
  try
    try
      Q.Connection := FB;

      try
        if OpenProductByDirectEAN(Q, Code) then
        begin
          ArtikelPreis := FieldFloatDef(Q, 'PREIS', 0);
          if ArtikelPreis <= 0 then
            ArtikelPreis := FieldFloatDef(Q, 'VK_BRUTTO', 0);

          Weight := FieldFloatDef(Q, 'NENNGEWICHT', 0);
          CalcPrice := ArtikelPreis;

          LogEichamtWeighing('EAN_SCAN_DIRECT', StrToIntDef(FieldStrDef(Q, 'ELENO', '0'), 0), FieldStrDef(Q, 'BEZEICHNUNG', ''), Weight, 0, Weight, '', Code, 'Direkt-EAN Preis=' + LogNumber(CalcPrice, '0.00'));
          Result := ProductJsonFromQuery(Q, 'Direkt-EAN', Weight, CalcPrice);
          Exit;
        end;
      except
        on E: Exception do
          LogError('LABEL SCAN Direkt-EAN Pruefung fehlgeschlagen: ' + E.Message);
      end;

      if Length(Code) <> 13 then
      begin
        Result := '{"ok":false,"message":"EAN nicht gefunden. Fuer Waagen-EAN werden 13 Stellen erwartet."}';
        Exit;
      end;

      if SCOConfig.CheckEANMod10 then
      begin
        CheckIst := StrToIntDef(Copy(Code, 13, 1), -1);
        CheckSoll := EAN13CheckDigit(Copy(Code, 1, 12));

        if CheckIst <> CheckSoll then
        begin
          LogError(
            'LABEL SCAN Mod10 Fehler EAN=' + Code +
            ' Erwartet=' + IntToStr(CheckSoll) +
            ' Gelesen=' + IntToStr(CheckIst)
          );

          Result :=
            '{"ok":false,"message":"EAN-Pruefziffer falsch. Erwartet: ' +
            IntToStr(CheckSoll) + ', gelesen: ' +
            IntToStr(CheckIst) + '."}';
          Exit;
        end;
      end;

      Prefix := Copy(Code, 1, 2);
      ArtikelText := Copy(Code, 3, 5);
      WertText := Copy(Code, 8, 5);

      Kennzahl := StrToIntDef(Prefix, 0);
      ArtikelNo := StrToIntDef(ArtikelText, 0);
      Wert := StrToIntDef(WertText, 0);

      if ArtikelNo <= 0 then
      begin
        Result := '{"ok":false,"message":"Artikelnummer im EAN ist ungueltig."}';
        Exit;
      end;

      if not OpenProductByArticleNo(Q, ArtikelNo) then
      begin
        Result :=
          '{"ok":false,"message":"Artikel ' + IntToStr(ArtikelNo) +
          ' aus Waagen-EAN nicht gefunden."}';
        Exit;
      end;

      ArtikelPreis := FieldFloatDef(Q, 'PREIS', 0);
      if ArtikelPreis <= 0 then
        ArtikelPreis := FieldFloatDef(Q, 'VK_BRUTTO', 0);

      IstPreisEAN := (Kennzahl mod 2) = 0;
      Weight := 0;
      EanPrice := 0;
      CalcPrice := 0;

      if IstPreisEAN then
      begin
        EanPrice := Wert / 100;
        CalcPrice := EanPrice;

        Weight := FieldFloatDef(Q, 'NENNGEWICHT', 0);

        if (Weight <= 0) and (ArtikelPreis > 0) then
          Weight := EanPrice / ArtikelPreis;

        LogEichamtWeighing('EAN_SCAN_PRICE', ArtikelNo, FieldStrDef(Q, 'BEZEICHNUNG', ''), Weight, 0, Weight, '', Code, 'Kennzahl=' + Prefix + ' Preis=' + LogNumber(CalcPrice, '0.00'));
        Result := ProductJsonFromQuery(Q, 'Preis-EAN ' + Prefix, Weight, CalcPrice);
      end
      else
      begin
        Weight := Wert / 1000;

        if ArtikelPreis > 0 then
          CalcPrice := Weight * ArtikelPreis;

        LogEichamtWeighing('EAN_SCAN_WEIGHT', ArtikelNo, FieldStrDef(Q, 'BEZEICHNUNG', ''), Weight, 0, Weight, '', Code, 'Kennzahl=' + Prefix + ' Preis=' + LogNumber(CalcPrice, '0.00'));
        Result := ProductJsonFromQuery(Q, 'Gewichts-EAN ' + Prefix, Weight, CalcPrice);
      end;

    except
      on E: Exception do
      begin
        LogError('LABEL SCAN ERROR: ' + E.Message);
        Result := '{"ok":false,"message":"Scanfehler: ' + JS(E.Message) + '"}';
      end;
    end;
  finally
    Q.Free;
  end;
end;

function LabelingReadWeightJson: string;
begin
  LogTransaction('LABEL WEIGHT READ');
  Result := ScaleReadWeightJson;
  LogWeighing('SCALE_READ ' + Result);
end;
function ReplaceZplValue(const Zpl, Name, Value: string): string;
begin
  Result := StringReplace(Zpl, '$' + Name + '$', Value, [rfReplaceAll, rfIgnoreCase]);
end;

function GermanDate(const S: string): string;
begin
  Result := S;
  if (Length(S) = 10) and (S[5] = '-') and (S[8] = '-') then
    Result := Copy(S, 9, 2) + '.' + Copy(S, 6, 2) + '.' + Copy(S, 1, 4);
end;

type
  TNutritionValues = record
    Kcal, Kjoule, Protein, Carbs, Sugar, Fat, Saturates, Salt, Fiber: Double;
  end;

function PadNumber(Value, Count: Integer): string;
begin
  Result := IntToStr(Abs(Value));
  while Length(Result) < Count do Result := '0' + Result;
  if Length(Result) > Count then Result := Copy(Result, Length(Result) - Count + 1, Count);
end;

function BuildEANFromPattern(const Pattern: string; PLU: Integer; Weight, Total: Double): string;
var P, Base, Run: string; I, J, Count, Value: Integer; C: Char;
begin
  P := UpperCase(Trim(Pattern));
  Base := '';
  I := 1;
  while I <= Length(P) do
  begin
    C := P[I];
    if C = 'Q' then begin Inc(I); Continue; end;
    if CharInSet(C, ['N','P','G']) then
    begin
      J := I;
      while (J <= Length(P)) and (P[J] = C) do Inc(J);
      Count := J - I;
      case C of
        'N': Value := PLU;
        'P': Value := Round(Total * 100);
      else
        Value := Round(Weight * 1000);
      end;
      Run := PadNumber(Value, Count);
      Base := Base + Run;
      I := J;
    end
    else
    begin
      if CharInSet(C, ['0'..'9']) then Base := Base + C;
      Inc(I);
    end;
  end;
  if Length(Base) > 12 then SetLength(Base, 12);
  while Length(Base) < 12 do Base := Base + '0';
  Result := Base + IntToStr(EAN13CheckDigit(Base));
end;

function GeneratedArticleEAN(PLU: Integer; Weight, Total: Double;
  const UnitText: string): string;
begin
  // Ungerade Kennzahl = Gewicht, gerade Kennzahl = Preis.
  if SameText(Trim(UnitText), 'kg') then
    Result := BuildEANFromPattern('21NNNNNGGGGGQ', PLU, Weight, Total)
  else
    Result := BuildEANFromPattern('22NNNNNPPPPPQ', PLU, Weight, Total);
end;

function ReplaceEANMarkers(const Zpl: string; PLU: Integer; Weight, Total: Double): string;
var A, B: Integer; Marker, Pattern: string;
begin
  Result := Zpl;
  while True do
  begin
    A := Pos('$EAN_', UpperCase(Result));
    if A <= 0 then Break;
    B := PosEx('$', Result, A + 5);
    if B <= A then Break;
    Marker := Copy(Result, A, B - A + 1);
    Pattern := Copy(Result, A + 5, B - A - 5);
    Result := StringReplace(Result, Marker, BuildEANFromPattern(Pattern, PLU, Weight, Total), [rfReplaceAll]);
  end;
end;

function ApplyPrintQuantity(const Zpl: string; Qty: Integer): string;
var
  P, NumberStart, NumberEnd, XZPos: Integer;
begin
  Result := Zpl;
  Qty := Max(1, Qty);
  P := Pos('^PQ', UpperCase(Result));
  if P > 0 then
  begin
    NumberStart := P + 3;
    NumberEnd := NumberStart;
    while (NumberEnd <= Length(Result)) and CharInSet(Result[NumberEnd], ['0'..'9']) do
      Inc(NumberEnd);
    Delete(Result, NumberStart, NumberEnd - NumberStart);
    Insert(IntToStr(Qty), Result, NumberStart);
  end
  else
  begin
    XZPos := Pos('^XZ', UpperCase(Result));
    if XZPos > 0 then
      Insert('^PQ' + IntToStr(Qty) + ',0,1,Y' + sLineBreak, Result, XZPos)
    else
      Result := Result + sLineBreak + '^PQ' + IntToStr(Qty) + ',0,1,Y';
  end;
end;
function CleanIngredientWord(const S: string): string;
var I: Integer;
begin
  Result := LowerCase(Trim(S));
  for I := Length(Result) downto 1 do
    if CharInSet(Result[I], [',',';',':','.','(',')','[',']','{','}']) then Delete(Result, I, 1);
end;

function IsAllergen(const Word, Csv: string): Boolean;
var A: TStringDynArray; X, W: string;
begin
  Result := False;
  W := CleanIngredientWord(Word);
  A := SplitString(LowerCase(Csv), ',');
  for X in A do
    if Trim(X) = W then Exit(True);
end;

function SafeZplText(const S: string): string;
begin
  Result := StringReplace(S, '^', ' ', [rfReplaceAll]);
  Result := StringReplace(Result, '~', ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
end;

function NormalizeIngredientText(const S: string): string;
var I: Integer; C, NextC: Char; LastWasSpace: Boolean;
begin
  Result := '';
  LastWasSpace := True;
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if CharInSet(C, [#9, #10, #13, ' ']) then
    begin
      if (Result <> '') and not LastWasSpace then Result := Result + ' ';
      LastWasSpace := True;
      Continue;
    end;
    Result := Result + C;
    LastWasSpace := False;
    if CharInSet(C, [',', ';', ':']) and (I < Length(S)) then
    begin
      NextC := S[I + 1];
      if not CharInSet(NextC, [#9, #10, #13, ' ']) then
      begin
        Result := Result + ' ';
        LastWasSpace := True;
      end;
    end;
  end;
  Result := Trim(Result);
end;

function RenderIngredients(const Marker, Ingredients: string): string;
var P, Words: TStringDynArray; X, Y, W, H, FH, FW, Gap, CurX, CurY, WordW: Integer;
    Style, Allergens, Prefix, Word: string; Bold: Boolean;
begin
  Result := '';
  if Trim(Ingredients) = '' then Exit;
  P := SplitString(Marker, '|');
  if Length(P) < 11 then Exit;
  X := StrToIntDef(P[1], 0); Y := StrToIntDef(P[2], 0); W := StrToIntDef(P[3], 300);
  H := StrToIntDef(P[4], 100); FH := StrToIntDef(P[5], 24); FW := StrToIntDef(P[6], FH);
  Gap := StrToIntDef(P[7], 2); Style := LowerCase(P[8]); Allergens := P[9]; Prefix := P[10];
  Words := SplitString(NormalizeIngredientText(Trim(Prefix + Ingredients)), ' ');
  CurX := X; CurY := Y;
  for Word in Words do
  begin
    if Word = '' then Continue;
    WordW := Max(Round(FW * 0.55), Round((Length(Word) * FW * 0.46) + (FW * 0.38)));
    if (CurX + WordW > X + W) and (CurX > X) then begin CurX := X; Inc(CurY, FH + Gap); end;
    if CurY + FH > Y + H then Break;
    Bold := IsAllergen(Word, Allergens);
    Result := Result + '^FO' + IntToStr(CurX) + ',' + IntToStr(CurY) +
      '^A0N,' + IntToStr(FH) + ',' + IntToStr(FW) + '^FD' + SafeZplText(Word) + '^FS' + sLineBreak;
    if Bold and (Style = 'bold') then
      Result := Result + '^FO' + IntToStr(CurX + 1) + ',' + IntToStr(CurY) +
        '^A0N,' + IntToStr(FH) + ',' + IntToStr(FW) + '^FD' + SafeZplText(Word) + '^FS' + sLineBreak;
    if Bold and (Style = 'underline') then
      Result := Result + '^FO' + IntToStr(CurX) + ',' + IntToStr(CurY + FH) +
        '^GB' + IntToStr(Max(2, WordW - Round(FW * 0.5))) + ',2,2^FS' + sLineBreak;
    Inc(CurX, WordW);
  end;
end;

function NutrText(V: Double; const UnitText: string): string;
begin
  Result := FormatFloat('0.##', V) + UnitText;
end;

function RenderNutrition(const Marker: string; const N: TNutritionValues): string;
var P: TStringDynArray; X, Y, W, H, FH, FW, Gap, RowY, RowH, I: Integer;
    Border: Boolean; Title: string;
  procedure AddRow(const Caption, Value: string);
  begin
    if RowY + RowH > Y + H then Exit;
    Result := Result + '^FO' + IntToStr(X + 4) + ',' + IntToStr(RowY) + '^A0N,' +
      IntToStr(FH) + ',' + IntToStr(FW) + '^FD' + Caption + '^FS' + sLineBreak;
    Result := Result + '^FO' + IntToStr(X + Round(W * 0.58)) + ',' + IntToStr(RowY) +
      '^A0N,' + IntToStr(FH) + ',' + IntToStr(FW) + '^FD' + Value + '^FS' + sLineBreak;
    if Border then Result := Result + '^FO' + IntToStr(X) + ',' + IntToStr(RowY + RowH - 2) +
      '^GB' + IntToStr(W) + ',1,1^FS' + sLineBreak;
    Inc(RowY, RowH);
  end;
begin
  Result := '';
  P := SplitString(Marker, '|');
  if Length(P) < 10 then Exit;
  X := StrToIntDef(P[1], 0); Y := StrToIntDef(P[2], 0); W := StrToIntDef(P[3], 350);
  H := StrToIntDef(P[4], 220); FH := StrToIntDef(P[5], 20); FW := StrToIntDef(P[6], FH);
  Gap := StrToIntDef(P[7], 2); Border := P[8] = '1'; Title := P[9]; RowH := FH + Gap + 2;
  if Border then Result := '^FO' + IntToStr(X) + ',' + IntToStr(Y) + '^GB' + IntToStr(W) + ',' + IntToStr(H) + ',2^FS' + sLineBreak;
  Result := Result + '^FO' + IntToStr(X + 4) + ',' + IntToStr(Y + 3) + '^A0N,' +
    IntToStr(FH + 2) + ',' + IntToStr(FW + 2) + '^FD' + SafeZplText(Title) + '^FS' + sLineBreak;
  RowY := Y + RowH;
  AddRow('Energie', NutrText(N.Kjoule, ' kJ / ') + NutrText(N.Kcal, ' kcal'));
  AddRow('Fett', NutrText(N.Fat, ' g'));
  AddRow('davon gesaettigt', NutrText(N.Saturates, ' g'));
  AddRow('Kohlenhydrate', NutrText(N.Carbs, ' g'));
  AddRow('davon Zucker', NutrText(N.Sugar, ' g'));
  AddRow('Eiweiss', NutrText(N.Protein, ' g'));
  AddRow('Salz', NutrText(N.Salt, ' g'));
end;

function ExpandFoodMarkers(const Zpl, Ingredients: string; const N: TNutritionValues): string;
var Lines: TStringList; I: Integer; Line: string;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := Zpl;
    Result := '';
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Lines[I];
      if StartsText('^FXFW_INGREDIENTS|', Line) then Result := Result + RenderIngredients(Line, Ingredients)
      else if StartsText('^FXFW_NUTRITION|', Line) then Result := Result + RenderNutrition(Line, N)
      else Result := Result + Line + sLineBreak;
    end;
  finally
    Lines.Free;
  end;
end;

procedure LoadNutrition(ArtikelID: Integer; out N: TNutritionValues);
var Q: TFDQuery;
begin
  FillChar(N, SizeOf(N), 0);
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text := 'select first 1 RZ_BRENNWERTKCAL, RZ_BRENNWERTKJOULE, RZ_EIWEISS, ' +
      'RZ_KOHLENHYDRATE, RZ_ZUCKER, RZ_FETT, RZ_FETTGESAETTIGT, RZ_SALZ, RZ_BALLAST ' +
      'from ARTIKEL where ID = :ID';
    Q.ParamByName('ID').AsInteger := ArtikelID;
    Q.Open;
    if not Q.IsEmpty then
    begin
      N.Kcal := FieldFloatDef(Q, 'RZ_BRENNWERTKCAL', 0);
      N.Kjoule := FieldFloatDef(Q, 'RZ_BRENNWERTKJOULE', 0);
      N.Protein := FieldFloatDef(Q, 'RZ_EIWEISS', 0);
      N.Carbs := FieldFloatDef(Q, 'RZ_KOHLENHYDRATE', 0);
      N.Sugar := FieldFloatDef(Q, 'RZ_ZUCKER', 0);
      N.Fat := FieldFloatDef(Q, 'RZ_FETT', 0);
      N.Saturates := FieldFloatDef(Q, 'RZ_FETTGESAETTIGT', 0);
      N.Salt := FieldFloatDef(Q, 'RZ_SALZ', 0);
      N.Fiber := FieldFloatDef(Q, 'RZ_BALLAST', 0);
    end;
  finally
    Q.Free;
  end;
end;

function RawPrintZplTcp(const Host: string; Port: Integer; const Zpl: string;
  out UsedPrinter: string): Boolean;
var
  TCP: TIdTCPClient;
begin
  Result := False;
  UsedPrinter := 'TCP ' + Trim(Host) + ':' + IntToStr(Port);
  TCP := TIdTCPClient.Create(nil);
  try
    TCP.Host := Trim(Host);
    TCP.Port := Port;
    TCP.ConnectTimeout := 2500;
    TCP.ReadTimeout := 2500;
    TCP.Connect;
    TCP.IOHandler.Write(Zpl, IndyTextEncoding_UTF8);
    Result := TCP.Connected;
  finally
    if TCP.Connected then TCP.Disconnect;
    TCP.Free;
  end;
end;

function LabelPrinterTestJson(const Host: string; Port: Integer; const WindowsPrinter: string): string;
var
  TCP: TIdTCPClient;
  H: THandle;
  Needed: DWORD;
  PrinterName, TestHost: string;
  TestPort: Integer;
begin
  try
    SCOConfig.Load;
    TestHost := Trim(Host);
    if TestHost = '' then TestHost := Trim(SCOConfig.LabelDruckerHost);
    TestPort := Port;
    if TestPort <= 0 then TestPort := SCOConfig.LabelDruckerPort;
    if TestPort <= 0 then TestPort := 9100;
    if TestHost <> '' then
    begin
      TCP := TIdTCPClient.Create(nil);
      try
        TCP.Host := TestHost;
        TCP.Port := TestPort;
        TCP.ConnectTimeout := 2500;
        TCP.ReadTimeout := 2500;
        TCP.Connect;
        Result := '{"ok":true,"message":"Zebra-Drucker erreichbar: ' +
          JS(TCP.Host) + ':' + IntToStr(TCP.Port) + '."}';
      finally
        if TCP.Connected then TCP.Disconnect;
        TCP.Free;
      end;
      Exit;
    end;

    PrinterName := Trim(WindowsPrinter);
    if PrinterName = '' then PrinterName := Trim(SCOConfig.LabelDrucker);
    if PrinterName = '' then
    begin
      Needed := 0;
      GetDefaultPrinter(nil, @Needed);
      if Needed = 0 then RaiseLastOSError;
      SetLength(PrinterName, Needed);
      if not GetDefaultPrinter(PChar(PrinterName), @Needed) then RaiseLastOSError;
      SetLength(PrinterName, StrLen(PChar(PrinterName)));
    end;
    H := 0;
    if not OpenPrinter(PChar(PrinterName), H, nil) then RaiseLastOSError;
    try
      Result := '{"ok":true,"message":"Windows-Drucker erreichbar: ' + JS(PrinterName) + '."}';
    finally
      ClosePrinter(H);
    end;
  except
    on E: Exception do
    begin
      LogError('LABEL PRINTER TEST ERROR: ' + E.Message);
      Result := '{"ok":false,"message":"Etikettendrucker nicht erreichbar: ' + JS(E.Message) + '"}';
    end;
  end;
end;
function RawPrintZpl(const PrinterName, Zpl: string; out UsedPrinter: string): Boolean;
var H: THandle; Doc: DOC_INFO_1; Written, Needed: DWORD; Data: UTF8String; PName: string;
begin
  Result := False;
  UsedPrinter := Trim(PrinterName);
  if UsedPrinter = '' then
  begin
    Needed := 0;
    GetDefaultPrinter(nil, @Needed);
    if Needed = 0 then RaiseLastOSError;
    SetLength(PName, Needed);
    if not GetDefaultPrinter(PChar(PName), @Needed) then RaiseLastOSError;
    SetLength(PName, StrLen(PChar(PName)));
    UsedPrinter := PName;
  end;
  H := 0;
  if not OpenPrinter(PChar(UsedPrinter), H, nil) then RaiseLastOSError;
  try
    FillChar(Doc, SizeOf(Doc), 0);
    Doc.pDocName := 'FOODWARE Etikett';
    Doc.pDatatype := 'RAW';
    if StartDocPrinter(H, 1, @Doc) = 0 then RaiseLastOSError;
    try
      if not StartPagePrinter(H) then RaiseLastOSError;
      Data := UTF8Encode(Zpl);
      Written := 0;
      if (Length(Data) > 0) and not WritePrinter(H, Pointer(Data), Length(Data), Written) then RaiseLastOSError;
      EndPagePrinter(H);
      Result := Written = DWORD(Length(Data));
    finally
      EndDocPrinter(H);
    end;
  finally
    ClosePrinter(H);
  end;
end;

function LabelingPrintJson(PLU: Integer; Weight: Double; Tara: Double; Qty: Integer;
  const MHD, TemplateName: string): string;
var
  Q: TFDQuery;
  Zpl, LabelName, UsedPrinter, MHDText, UnitText, EANText, LabelTag: string;
  TemplateNo, MHDDays, ArtikelID: Integer;
  UnitPrice, Total: Double;
  Nutrition: TNutritionValues;
begin
  Q := TFDQuery.Create(nil);
  try
    try
      SCOConfig.Load;
      Q.Connection := FB;
      Q.SQL.Text :=
        'select first 1 ID, NUMMER, BEZEICHNUNG, BEZEICHNUNG2, EAN, ZUTATENTEXT, ' +
        'ME_BEZ, VK_BRUTTO, NENNGEWICHT, STANDARD_ETIKETT, MHD ' +
        'from VARTIKEL where trim(cast(NUMMER as varchar(20))) = :PLU ' +
        'or trim(cast(ELENO as varchar(20))) = :PLU';
      Q.ParamByName('PLU').AsString := IntToStr(PLU);
      Q.Open;
      if Q.IsEmpty then raise Exception.Create('Artikel fuer Etikett nicht gefunden.');
      ArtikelID := Q.FieldByName('ID').AsInteger;
      LoadNutrition(ArtikelID, Nutrition);

      TemplateNo := StrToIntDef(TemplateName, 0);
      if TemplateNo <= 0 then TemplateNo := StrToIntDef(FieldStrDef(Q, 'STANDARD_ETIKETT', '0'), 0);
      if TemplateNo <= 0 then raise Exception.Create('Dem Artikel ist keine Etikettenvorlage zugewiesen.');
      Zpl := LabelTemplateZplByNumber(TemplateNo, LabelName);
      if Trim(Zpl) = '' then raise Exception.Create('Etikettenvorlage ' + IntToStr(TemplateNo) + ' wurde nicht gefunden oder noch nicht gespeichert.');

      UnitPrice := FieldFloatDef(Q, 'VK_BRUTTO', 0);
      UnitText := FieldStrDef(Q, 'ME_BEZ', 'Stck');
      if SameText(UnitText, 'kg') then Total := Weight * UnitPrice else Total := UnitPrice;
      MHDText := MHD;
      if MHDText = '' then
      begin
        MHDDays := StrToIntDef(FieldStrDef(Q, 'MHD', '0'), 0);
        if MHDDays > 0 then MHDText := FormatDateTime('yyyy-mm-dd', Date + MHDDays);
      end;
      LabelTag := GenerateLabelTag13;
      EANText := DigitsOnly(FieldStrDef(Q, 'EAN', ''));
      if EANText = '' then
        EANText := GeneratedArticleEAN(PLU, Weight, Total, UnitText);
      Zpl := ReplaceZplValue(Zpl, 'artikel', FieldStrDef(Q, 'BEZEICHNUNG', ''));
      Zpl := ReplaceZplValue(Zpl, 'artikel2', FieldStrDef(Q, 'BEZEICHNUNG2', ''));
      Zpl := ReplaceZplValue(Zpl, 'plu', IntToStr(PLU));
      Zpl := ReplaceZplValue(Zpl, 'ean', EANText);
      Zpl := ReplaceZplValue(Zpl, 'gewicht', FormatFloat('0.000', Weight) + ' kg');
      Zpl := ReplaceZplValue(Zpl, 'fuellgewicht', FormatFloat('0.000', FieldFloatDef(Q, 'NENNGEWICHT', 0)) + ' kg');
      Zpl := ReplaceZplValue(Zpl, 'fuellgewichtG', FormatFloat('0', FieldFloatDef(Q, 'NENNGEWICHT', 0) * 1000) + ' g');
      Zpl := ReplaceZplValue(Zpl, 'tara', FormatFloat('0.000', Tara));
      Zpl := ReplaceZplValue(Zpl, 'netto', FormatFloat('0.000', Weight) + ' kg');
      Zpl := ReplaceZplValue(Zpl, 'preisKg', FormatFloat('0.00', UnitPrice) + ' EUR/' + UnitText);
      Zpl := ReplaceZplValue(Zpl, 'preis100g', FormatFloat('0.00', UnitPrice / 10) + ' EUR/100 g');
      Zpl := ReplaceZplValue(Zpl, 'preis', FormatFloat('0.00', Total) + ' EUR');
      Zpl := ReplaceZplValue(Zpl, 'mhd', GermanDate(MHDText));
      Zpl := ReplaceZplValue(Zpl, 'einheit', UnitText);
      Zpl := ReplaceZplValue(Zpl, 'zutaten', FieldStrDef(Q, 'ZUTATENTEXT', ''));
      Zpl := ReplaceZplValue(Zpl, 'temperatur', '');
      Zpl := ReplaceEANMarkers(Zpl, PLU, Weight, Total);
      Zpl := ExpandFoodMarkers(Zpl, FieldStrDef(Q, 'ZUTATENTEXT', ''), Nutrition);
      Zpl := StringReplace(Zpl, '$WRITE_RFID$', '', [rfReplaceAll, rfIgnoreCase]);
      Zpl := ApplyPrintQuantity(Zpl, Qty);

      if (not SameText(TemplateName, 'rfid')) and SCOConfig.EANLabelWriteTagInfo then
        SaveNormalLabelInfo(PLU, Weight, Tara, MHDText, LabelTag);
      if Trim(SCOConfig.LabelDruckerHost) <> '' then
      begin
        if not RawPrintZplTcp(SCOConfig.LabelDruckerHost, SCOConfig.LabelDruckerPort, Zpl, UsedPrinter) then
          raise Exception.Create('ZPL konnte nicht vollstaendig per TCP an den Drucker gesendet werden.');
      end
      else if not RawPrintZpl(SCOConfig.LabelDrucker, Zpl, UsedPrinter) then
        raise Exception.Create('ZPL konnte nicht vollstaendig an den Windows-Drucker gesendet werden.');

      LogTransaction('LABEL PRINT OK PLU=' + IntToStr(PLU) + ' TEMPLATE=' + IntToStr(TemplateNo) + ' PRINTER=' + UsedPrinter);
      LogWeighing('LABEL_PRINT_OK PLU=' + IntToStr(PLU) + ' ARTIKEL=' + FieldStrDef(Q, 'BEZEICHNUNG', '') + ' BRUTTO=' + LogNumber(Weight + Tara, '0.000') + 'kg TARA=' + LogNumber(Tara, '0.000') + 'kg NETTO=' + LogNumber(Weight, '0.000') + 'kg QTY=' + IntToStr(Qty) + ' EINZELPREIS=' + LogNumber(UnitPrice, '0.00') + ' GESAMT=' + LogNumber(Total, '0.00') + ' EAN=' + EANText + ' MHD=' + MHDText + ' TEMPLATE=' + IntToStr(TemplateNo) + ' LABEL=' + LabelName + ' PRINTER=' + UsedPrinter);
      LogEichamtWeighing('LABEL_PRINT', PLU, FieldStrDef(Q, 'BEZEICHNUNG', ''), Weight + Tara, Tara, Weight, '', EANText, 'qty=' + IntToStr(Qty) + ' total=' + LogNumber(Total, '0.00') + ' template=' + IntToStr(TemplateNo));
      Result := '{"ok":true,"message":"Etikett ' + JS(LabelName) + ' wurde gedruckt.","plu":' +
        IntToStr(PLU) + ',"templateNumber":' + IntToStr(TemplateNo) + ',"printer":"' + JS(UsedPrinter) + '"}';
    except
      on E: Exception do
      begin
        LogError('LABEL PRINT ERROR: ' + E.Message);
        LogWeighing('LABEL_PRINT_ERROR PLU=' + IntToStr(PLU) + ' BRUTTO=' + LogNumber(Weight + Tara, '0.000') + 'kg TARA=' + LogNumber(Tara, '0.000') + 'kg NETTO=' + LogNumber(Weight, '0.000') + 'kg ERROR=' + E.Message);
        Result := '{"ok":false,"message":"' + JS(E.Message) + '"}';
      end;
    end;
  finally
    Q.Free;
  end;
end;

function LabelingWriteRfidJson(PLU: Integer; Weight: Double): string;
begin
  try
    LogTransaction(
      'RFID WRITE PLU=' + IntToStr(PLU) +
      ' Weight=' + FloatToStr(Weight)
    );
    // TODO:
    // Zebra ZD621R / RFID Codierung:
    // EPL/ZPL/RFID-Befehl oder Druckertreiber/SDK anbinden.
    Result :=
      '{' +
      '"ok":true,' +
      '"message":"RFID-Tag wurde codiert.",' +
      '"plu":' + IntToStr(PLU) +
      '}';
  except
    on E: Exception do
    begin
      LogError('RFID WRITE ERROR: ' + E.Message);
      Result :=
        '{' +
        '"ok":false,' +
        '"message":"' + JS(E.Message) + '"' +
        '}';
    end;
  end;
end;

function FieldDateJson(Q: TFDQuery; const FieldName: string): string;
begin
  if Q.FieldByName(FieldName).IsNull then
    Result := ''
  else
    Result := FormatDateTime('dd.mm.yyyy hh:nn:ss', Q.FieldByName(FieldName).AsDateTime);
end;
function FieldDateOnlyJson(Q: TFDQuery; const FieldName: string): string;
begin
  if Q.FieldByName(FieldName).IsNull then
    Result := ''
  else
    Result := FormatDateTime('dd.mm.yyyy', Q.FieldByName(FieldName).AsDateTime);
end;
function LabelingProtocolJsonInternal(Limit: Integer): string;
var
  Q: TFDQuery;
  First: Boolean;
  SQLLimit: string;
begin
  if Limit <= 0 then
    Limit := 500;
  if Limit > 2000 then
    Limit := 2000;
  SQLLimit := IntToStr(Limit);
  LogTransaction('LABEL PROTOCOL LIST LIMIT=' + SQLLimit);
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'select first ' + SQLLimit + ' ' +
      '  r.ID, r.TAG, r.MHD, r.TYP, r.GEWICHT, r.TARA, r.PREIS, r.NUMMER, r.STATUS, ' +
      '  r.CREATEDATE, r.CHANGEDATE, r.CHARGE ' +
      'from TAGINFO r ' +
      'order by r.CREATEDATE desc';
    Q.Open;
    Result := '[';
    First := True;
    while not Q.Eof do
    begin
      if not First then
        Result := Result + ',';
      Result := Result +
        '{' +
        '"id":' + SafeJsonNumber(FieldStrDef(Q, 'ID', '0'), '0') + ',' +
        '"tag":"' + JS(Q.FieldByName('TAG').AsString) + '",' +
        '"mhd":"' + JS(FieldDateOnlyJson(Q, 'MHD')) + '",' +
        '"typ":' + Trim(Q.FieldByName('TYP').AsString) + ',' +
        '"weight":' + FloatJson(Q.FieldByName('GEWICHT').AsFloat) + ',' +
        '"gewicht":' + FloatJson(Q.FieldByName('GEWICHT').AsFloat) + ',' +
        '"tara":' + FloatJson(FieldFloatDef(Q, 'TARA', 0)) + ',' +
        '"price":' + PriceJson(Q.FieldByName('PREIS').AsFloat) + ',' +
        '"preis":' + PriceJson(Q.FieldByName('PREIS').AsFloat) + ',' +
        '"number":"' + JS(Q.FieldByName('NUMMER').AsString) + '",' +
        '"nummer":"' + JS(Q.FieldByName('NUMMER').AsString) + '",' +
        '"status":' + Trim(Q.FieldByName('STATUS').AsString) + ',' +
        '"createdate":"' + JS(FieldDateJson(Q, 'CREATEDATE')) + '",' +
        '"changedate":"' + JS(FieldDateJson(Q, 'CHANGEDATE')) + '",' +
        '"time":"' + JS(FormatDateTime('hh:nn', Q.FieldByName('CREATEDATE').AsDateTime)) + '",' +
        '"charge":"' + JS(Trim(Q.FieldByName('CHARGE').AsString)) + '"' +
        '}';
      First := False;
      Q.Next;
    end;
    Result := Result + ']';
  except
    on E: Exception do
    begin
      LogError('LABEL PROTOCOL LIST ERROR: ' + E.Message);
      Result := '[]';
    end;
  end;
  Q.Free;
end;
function LabelingProtocolJson(Limit: Integer): string;
begin
  LabelingDBLock.Acquire;
  try
    Result := LabelingProtocolJsonInternal(Limit);
  finally
    LabelingDBLock.Release;
  end;
end;
function LabelingProtocolDeleteJson(ID: Integer): string;
var
  Q: TFDQuery;
begin
  LogTransaction('LABEL PROTOCOL DELETE ID=' + IntToStr(ID));
  if ID <= 0 then
  begin
    Result := '{"ok":false,"message":"Ungueltige ID."}';
    Exit;
  end;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text := 'delete from TAGINFO where ID = :ID';
    Q.ParamByName('ID').AsInteger := ID;
    Q.ExecSQL;
    Result := '{"ok":true,"message":"Protokolleintrag geloescht."}';
  except
    on E: Exception do
    begin
      LogError('LABEL PROTOCOL DELETE ERROR: ' + E.Message);
      Result := '{"ok":false,"message":"' + JS(E.Message) + '"}';
    end;
  end;
  Q.Free;
end;
function LabelingProtocolStatusJson(ID, Status: Integer): string;
var
  Q: TFDQuery;
begin
  LogTransaction('LABEL PROTOCOL STATUS ID=' + IntToStr(ID) + ' STATUS=' + IntToStr(Status));
  if ID <= 0 then
  begin
    Result := '{"ok":false,"message":"Ungueltige ID."}';
    Exit;
  end;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'update TAGINFO set STATUS = :STATUS, CHANGEDATE = CURRENT_TIMESTAMP where ID = :ID';
    Q.ParamByName('STATUS').AsInteger := Status;
    Q.ParamByName('ID').AsInteger := ID;
    Q.ExecSQL;
    Result := '{"ok":true,"message":"Status geaendert."}';
  except
    on E: Exception do
    begin
      LogError('LABEL PROTOCOL STATUS ERROR: ' + E.Message);
      Result := '{"ok":false,"message":"' + JS(E.Message) + '"}';
    end;
  end;
  Q.Free;
end;
initialization
  LabelingDBLock := TCriticalSection.Create;

finalization
  LabelingDBLock.Free;

end.
