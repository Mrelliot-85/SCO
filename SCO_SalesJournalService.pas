unit SCO_SalesJournalService;
interface
uses
  System.SysUtils, System.JSON, FireDAC.Comp.Client;
type
  TSCOSalesJournalService = class
  private
    function BoolJson(Value: Boolean): string;
    function JS(const S: string): string;
    function TextValue(O: TJSONObject; const Name, Default: string): string;
    function FloatValue(O: TJSONObject; const Name: string; Default: Double): Double;
    function IntValue(O: TJSONObject; const Name: string; Default: Integer): Integer;
    function NextBonNo: Integer;
    procedure SetStringIfExists(Q: TFDQuery; const FieldName, Value: string);
    procedure SetIntegerIfExists(Q: TFDQuery; const FieldName: string; Value: Integer);
    procedure SetFloatIfExists(Q: TFDQuery; const FieldName: string; Value: Double);
    procedure SetDateTimeIfExists(Q: TFDQuery; const FieldName: string; Value: TDateTime);
    procedure WriteUmsatzPosition(BonNo, PosNo: Integer; Item: TJSONObject; const Payment: string);
    procedure MarkRfidTagSold(const Tag: string);
    function ShouldWriteBonjournal: Boolean;
    function ShouldWriteWebUI: Boolean;
    function ConnectWebUI: TFDConnection;
    procedure AddWebUIMeldung(const Art, Meldung: string);
    procedure AddWebUIStatus(Status, Bon, Pos, PLU: Integer; const TID, Artikel, Bezeichnung: string; Menge, EP, GP: Double);
    function JsonResult(AOk: Boolean; const AMessage: string; ABonNo: Integer): string;
  public
    function CompleteSaleFromJson(const JsonText: string): string;
    function WebStatusFromJson(const JsonText: string): string;
    function RfidScanJson(const Tag: string; Antenna: Integer): string;
    function RfidReleaseJson(const Tag: string): string;
  end;
implementation
uses
  System.Classes,
  System.DateUtils,
  System.SyncObjs,
  FireDAC.Stan.Def,
  FireDAC.Stan.Intf,
  FireDAC.Phys,
  FireDAC.Phys.MySQL,
  FireDAC.Phys.MySQLDef,
  SCO_CONFIG,
  SCO_DB,
  SCO_Logger;

var
  RfidScanLock: TCriticalSection;
function TSCOSalesJournalService.BoolJson(Value: Boolean): string;
begin
  if Value then Result := 'true' else Result := 'false';
end;
function TSCOSalesJournalService.JS(const S: string): string;
begin
  Result := S;
  Result := StringReplace(Result, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '"', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
end;
function TSCOSalesJournalService.TextValue(O: TJSONObject; const Name, Default: string): string;
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
function TSCOSalesJournalService.FloatValue(O: TJSONObject; const Name: string; Default: Double): Double;
var
  S: string;
begin
  S := StringReplace(TextValue(O, Name, ''), '.', ',', [rfReplaceAll]);
  Result := StrToFloatDef(S, Default);
end;
function TSCOSalesJournalService.IntValue(O: TJSONObject; const Name: string; Default: Integer): Integer;
begin
  Result := StrToIntDef(TextValue(O, Name, ''), Default);
end;
function TSCOSalesJournalService.JsonResult(AOk: Boolean; const AMessage: string; ABonNo: Integer): string;
begin
  Result := '{"ok":' + BoolJson(AOk) + ',"message":"' + JS(AMessage) + '","bonNo":' + IntToStr(ABonNo) + '}';
end;
function TSCOSalesJournalService.ShouldWriteBonjournal: Boolean;
begin
  Result := (not SCOConfig.DemoModus) or SCOConfig.DemoBonjournalSchreiben;
end;

function TSCOSalesJournalService.ShouldWriteWebUI: Boolean;
begin
  Result := (not SCOConfig.DemoModus) or SCOConfig.DemoWebUISchreiben;
end;

procedure TSCOSalesJournalService.SetStringIfExists(Q: TFDQuery; const FieldName, Value: string);
begin
  if Q.FindField(FieldName) <> nil then
    Q.FieldByName(FieldName).AsString := Value;
end;
procedure TSCOSalesJournalService.SetIntegerIfExists(Q: TFDQuery; const FieldName: string; Value: Integer);
begin
  if Q.FindField(FieldName) <> nil then
    Q.FieldByName(FieldName).AsInteger := Value;
end;
procedure TSCOSalesJournalService.SetFloatIfExists(Q: TFDQuery; const FieldName: string; Value: Double);
begin
  if Q.FindField(FieldName) <> nil then
    Q.FieldByName(FieldName).AsFloat := Value;
end;
procedure TSCOSalesJournalService.SetDateTimeIfExists(Q: TFDQuery; const FieldName: string; Value: TDateTime);
begin
  if Q.FindField(FieldName) <> nil then
    Q.FieldByName(FieldName).AsDateTime := Value;
end;
function TSCOSalesJournalService.NextBonNo: Integer;
var
  Q: TFDQuery;
begin
  Result := 1;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text := 'select coalesce(max(BONNO), 0) + 1 as BONNO from UC3_UMSATZ where FILIAL_ID = :FID';
    Q.ParamByName('FID').AsString := SCOConfig.BonjournalFilialId;
    Q.Open;
    if not Q.IsEmpty then
      Result := Q.FieldByName('BONNO').AsInteger;
  finally
    Q.Free;
  end;
end;
procedure TSCOSalesJournalService.WriteUmsatzPosition(BonNo, PosNo: Integer; Item: TJSONObject; const Payment: string);
var
  Q: TFDQuery;
  EP, GP, Menge: Double;
  PLU, WG, MWST: Integer;
  TenderName: string;
begin
  EP := FloatValue(Item, 'ep', 0);
  GP := FloatValue(Item, 'gp', 0);
  Menge := FloatValue(Item, 'qty', 1);
  PLU := IntValue(Item, 'plu', 0);
  WG := IntValue(Item, 'wg', IntValue(Item, 'group', 0));
  MWST := IntValue(Item, 'vatRate', IntValue(Item, 'mwst', 7));
  if MWST <> 19 then MWST := 7;
  TenderName := 'EC';
  if SameText(Payment, 'Bargeld') or SameText(Payment, 'bar') then
    TenderName := 'BAR';
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text := 'select first 1 * from UC3_UMSATZ where 1 = 0';
    Q.Open;
    Q.Append;
    SetStringIfExists(Q, 'FILIAL_ID', SCOConfig.BonjournalFilialId);
    SetStringIfExists(Q, 'GERAET', IntToStr(SCOConfig.ZVT_Kasse));
    SetDateTimeIfExists(Q, 'DATUM', Now);
    SetIntegerIfExists(Q, 'BONNO', BonNo);
    SetDateTimeIfExists(Q, 'ZEIT', TimeOf(Now));
    SetStringIfExists(Q, 'BEDIENER', IntToStr(SCOConfig.ZVT_Kasse));
    SetStringIfExists(Q, 'ARTNR', IntToStr(PLU));
    SetStringIfExists(Q, 'MWST', IntToStr(MWST));
    SetStringIfExists(Q, 'ME', TextValue(Item, 'unit', ''));
    SetStringIfExists(Q, 'WGNO', IntToStr(WG));
    SetFloatIfExists(Q, 'EPN', 0);
    SetFloatIfExists(Q, 'GPN', 0);
    SetIntegerIfExists(Q, 'SEQUENZ', 2);
    SetIntegerIfExists(Q, 'KUNDEN', 0);
    SetStringIfExists(Q, 'POSTEN', '0');
    SetIntegerIfExists(Q, 'ZEILENSTORNO', 0);
    SetIntegerIfExists(Q, 'NULLBONS', 1);
    SetIntegerIfExists(Q, 'STORNO', 0);
    SetIntegerIfExists(Q, 'WT', DayOfTheWeek(Date));
    SetStringIfExists(Q, 'KZ_ANGEBOT', 'F');
    SetIntegerIfExists(Q, 'SALES_TYPE', 2);
    SetIntegerIfExists(Q, 'SA_NUMMER', 0);
    SetFloatIfExists(Q, 'RABATT', 0);
    SetDateTimeIfExists(Q, 'BUCHDATUM', Now);
    SetDateTimeIfExists(Q, 'BUCHZEIT', TimeOf(Now));
    SetFloatIfExists(Q, 'RABATTA', 0);
    SetFloatIfExists(Q, 'RABATTP', 0);
    SetIntegerIfExists(Q, 'JAHR', YearOf(Now));
    SetIntegerIfExists(Q, 'MONAT', MonthOf(Now));
    SetIntegerIfExists(Q, 'VOID_STATE', 0);
    SetIntegerIfExists(Q, 'RABATTNO', 0);
    SetIntegerIfExists(Q, 'HERKUNFT', 1);
    SetIntegerIfExists(Q, 'WB_NO', 0);
    SetIntegerIfExists(Q, 'KK_VERBUCHT', 0);
    SetIntegerIfExists(Q, 'TENDERNO', 1);
    SetStringIfExists(Q, 'TENDERNAME', TenderName);
    SetFloatIfExists(Q, 'EP', EP);
    SetFloatIfExists(Q, 'GP', GP);
    SetFloatIfExists(Q, 'MENGE', Menge);
    SetIntegerIfExists(Q, 'POSNO', PosNo);
    SetIntegerIfExists(Q, 'STUNDE', HourOf(Now));
    Q.Post;
  finally
    Q.Free;
  end;
end;
procedure TSCOSalesJournalService.MarkRfidTagSold(const Tag: string);
var
  Q: TFDQuery;
  CleanTag: string;
begin
  CleanTag := Trim(Tag);
  if CleanTag = '' then
    Exit;
  ConnectDB;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text := 'UPDATE TAGINFO SET STATUS = 1 WHERE TAG STARTING WITH :TAG';
    Q.ParamByName('TAG').AsString := CleanTag;
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;
function TSCOSalesJournalService.ConnectWebUI: TFDConnection;
begin
  Result := nil;
  SCOConfig.Load;
  if not ShouldWriteWebUI then
  begin
    LogTransaction('WEBUI SKIP DemoModus=' + BoolToStr(SCOConfig.DemoModus, True) + ' DemoWebUISchreiben=' + BoolToStr(SCOConfig.DemoWebUISchreiben, True));
    Exit;
  end;
  if not SCOConfig.WebUIAktiv then
    Exit;
  if (Trim(SCOConfig.WebUIHost) = '') or (Trim(SCOConfig.WebUIDatabase) = '') then
    Exit;
  Result := TFDConnection.Create(nil);
  try
    Result.LoginPrompt := False;
    Result.Params.DriverID := 'MySQL';
    Result.Params.Values['Server'] := SCOConfig.WebUIHost;
    Result.Params.Values['Port'] := IntToStr(SCOConfig.WebUIPort);
    Result.Params.Values['Database'] := SCOConfig.WebUIDatabase;
    Result.Params.Values['User_Name'] := SCOConfig.WebUIUser;
    Result.Params.Values['Password'] := SCOConfig.WebUIPassword;
    Result.ResourceOptions.AutoReconnect := True;
    Result.Connected := True;
  except
    Result.Free;
    raise;
  end;
end;
procedure TSCOSalesJournalService.AddWebUIMeldung(const Art, Meldung: string);
var
  Conn: TFDConnection;
  Q: TFDQuery;
begin
  Conn := ConnectWebUI;
  if not Assigned(Conn) then Exit;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text := 'INSERT INTO `Status`(`KUNDE`,`DATUM`,`UHRZEIT`,`ART`,`MELDUNG`) VALUES (:KUNDE,:DATUM,:UHRZEIT,:ART,:MELDUNG)';
    Q.ParamByName('KUNDE').AsInteger := SCOConfig.KundenNr;
    Q.ParamByName('DATUM').AsDate := Date;
    Q.ParamByName('UHRZEIT').AsTime := Time;
    Q.ParamByName('ART').AsString := Art;
    Q.ParamByName('MELDUNG').AsString := Meldung;
    Q.ExecSQL;
  finally
    Q.Free;
    Conn.Free;
  end;
end;
procedure TSCOSalesJournalService.AddWebUIStatus(Status, Bon, Pos, PLU: Integer; const TID, Artikel, Bezeichnung: string; Menge, EP, GP: Double);
var
  Conn: TFDConnection;
  Q: TFDQuery;
begin
  Conn := ConnectWebUI;
  if not Assigned(Conn) then Exit;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text :=
      'INSERT INTO `Transaktionen` ' +
      '(`KUNDE`,`DATUM`,`ZEIT`,`BON`,`POS`,`PLU`,`ARTIKEL`,`MENGE`,`EP`,`GP`,`TID`,`STATUS`,`BEZEICHNUNG`,`DAUER`) ' +
      'VALUES (:KUNDE,:DATUM,:ZEIT,:BON,:POS,:PLU,:ARTIKEL,:MENGE,:EP,:GP,:TID,:STATUS,:BEZEICHNUNG,:DAUER)';
    Q.ParamByName('KUNDE').AsInteger := SCOConfig.KundenNr;
    Q.ParamByName('DATUM').AsDate := Date;
    Q.ParamByName('ZEIT').AsTime := Time;
    Q.ParamByName('BON').AsInteger := Bon;
    Q.ParamByName('POS').AsInteger := Pos;
    Q.ParamByName('PLU').AsInteger := PLU;
    Q.ParamByName('ARTIKEL').AsString := Artikel;
    Q.ParamByName('MENGE').AsFloat := Menge;
    Q.ParamByName('EP').AsFloat := EP;
    Q.ParamByName('GP').AsFloat := GP;
    Q.ParamByName('TID').AsString := TID;
    Q.ParamByName('STATUS').AsInteger := Status;
    Q.ParamByName('BEZEICHNUNG').AsString := Bezeichnung;
    Q.ParamByName('DAUER').AsInteger := 0;
    Q.ExecSQL;
  finally
    Q.Free;
    Conn.Free;
  end;
end;
function TSCOSalesJournalService.CompleteSaleFromJson(const JsonText: string): string;
var
  V: TJSONValue;
  Root, Item: TJSONObject;
  Items: TJSONArray;
  I, BonNo, PLU: Integer;
  Payment: string;
  WriteJournal, WriteWebUI: Boolean;
begin
  BonNo := 0;
  Result := JsonResult(False, 'Verkauf konnte nicht verbucht werden.', BonNo);
  V := TJSONObject.ParseJSONValue(JsonText);
  try
    if not (V is TJSONObject) then
      Exit(JsonResult(False, 'Ungueltige Verkaufsdaten.', BonNo));
    Root := TJSONObject(V);
    Items := Root.GetValue<TJSONArray>('items');
    if not Assigned(Items) or (Items.Count = 0) then
      Exit(JsonResult(False, 'Keine Artikel zum Verbuchen vorhanden.', BonNo));

    SCOConfig.Load;
    WriteJournal := ShouldWriteBonjournal;
    WriteWebUI := ShouldWriteWebUI;

    LogTransaction(
      'SALE COMPLETE START Items=' + IntToStr(Items.Count) +
      ' DemoModus=' + BoolToStr(SCOConfig.DemoModus, True) +
      ' WriteJournal=' + BoolToStr(WriteJournal, True) +
      ' WriteWebUI=' + BoolToStr(WriteWebUI, True)
    );

    if WriteJournal then
    begin
      ConnectDB;
      BonNo := NextBonNo;
    end
    else
    begin
      BonNo := IntValue(Root, 'bonNo', 0);
      LogTransaction('BONJOURNAL SKIP DemoModus=' + BoolToStr(SCOConfig.DemoModus, True) +
        ' DemoBonjournalSchreiben=' + BoolToStr(SCOConfig.DemoBonjournalSchreiben, True));
    end;

    Payment := TextValue(Root, 'payment', '');

    for I := 0 to Items.Count - 1 do
    begin
      if not (Items.Items[I] is TJSONObject) then Continue;
      Item := TJSONObject(Items.Items[I]);

      if WriteJournal then
        WriteUmsatzPosition(BonNo, I + 1, Item, Payment);

      if TextValue(Item, 'tag', '') <> '' then
        MarkRfidTagSold(TextValue(Item, 'tag', ''));

      if WriteWebUI then
      begin
        PLU := IntValue(Item, 'plu', 0);
        try
          AddWebUIStatus(3, BonNo, I + 1, PLU, TextValue(Item, 'tag', ''), TextValue(Item, 'name', ''), 'Artikel gekauft', FloatValue(Item, 'qty', 1), FloatValue(Item, 'ep', 0), FloatValue(Item, 'gp', 0));
        except
          on E: Exception do LogError('WEBUI STATUS KAUF ERROR ' + E.Message);
        end;
      end;
    end;

    if WriteWebUI then
    begin
      try
        AddWebUIMeldung('Bonjournal', 'Bon ' + IntToStr(BonNo) + ' verbucht.');
      except
        on E: Exception do LogError('WEBUI MELDUNG ERROR ' + E.Message);
      end;
    end;

    LogTransaction('SALE COMPLETE END BonNo=' + IntToStr(BonNo) + ' Items=' + IntToStr(Items.Count));
    Result := JsonResult(True, 'Verkauf verbucht.', BonNo);
  except
    on E: Exception do
    begin
      LogError('SALE COMPLETE ERROR ' + E.ClassName + ': ' + E.Message);
      Result := JsonResult(False, 'Verkaufsbuchung Fehler: ' + E.Message, BonNo);
    end;
  end;
  V.Free;
end;
function TSCOSalesJournalService.WebStatusFromJson(const JsonText: string): string;
var
  V: TJSONValue;
  O: TJSONObject;
begin
  Result := JsonResult(False, 'Status konnte nicht geschrieben werden.', 0);
  V := TJSONObject.ParseJSONValue(JsonText);
  try
    if not (V is TJSONObject) then Exit;
    O := TJSONObject(V);
    AddWebUIStatus(
      IntValue(O, 'status', 1),
      IntValue(O, 'bon', 0),
      IntValue(O, 'pos', 0),
      IntValue(O, 'plu', 0),
      TextValue(O, 'tag', ''),
      TextValue(O, 'name', ''),
      TextValue(O, 'message', ''),
      FloatValue(O, 'qty', 0),
      FloatValue(O, 'ep', 0),
      FloatValue(O, 'gp', 0)
    );
    Result := JsonResult(True, 'Status geschrieben.', 0);
  except
    on E: Exception do
      Result := JsonResult(False, 'Status Fehler: ' + E.Message, 0);
  end;
  V.Free;
end;
function TSCOSalesJournalService.RfidReleaseJson(const Tag: string): string;
var
  Q: TFDQuery;
  CleanTag: string;
  Affected: Integer;
begin
  CleanTag := Trim(Tag);
  if CleanTag = '' then
    Exit('{"ok":false,"message":"Kein RFID-Tag uebergeben."}');
  try
    SCOConfig.Load;
    ConnectDB;
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := FB;
      Q.SQL.Text := 'UPDATE TAGINFO SET STATUS = 0 WHERE TAG STARTING WITH :TAG';
      Q.ParamByName('TAG').AsString := CleanTag;
      Q.ExecSQL;
      Affected := Q.RowsAffected;
    finally
      Q.Free;
    end;
    Result := '{"ok":true,"message":"RFID-Tag wurde freigegeben.","rows":' + IntToStr(Affected) + '}';
  except
    on E: Exception do
    begin
      LogError('RFID RELEASE ERROR ' + E.ClassName + ': ' + E.Message);
      Result := '{"ok":false,"message":"RFID-Freigabe Fehler: ' + JS(E.Message) + '"}';
    end;
  end;
end;
function TSCOSalesJournalService.RfidScanJson(const Tag: string; Antenna: Integer): string;
var
  Q, Info: TFDQuery;
  CleanTag, ActualTag, Name, UnitName, FailMessage: string;
  PLU, WG, MWST, TagStatus, TagNummer: Integer;
  Weight, EP, GP, TagPrice: Double;
  Alarm: Boolean;
begin
  RfidScanLock.Enter;
  try
    CleanTag := Trim(Tag);
    SCOConfig.Load;
    Alarm := SCOConfig.RFIDExitAlarmActive and (Antenna = SCOConfig.RFIDExitAlarmAntenna);
  if not SCOConfig.RFIDAktiv then
    Exit('{"ok":false,"message":"RFID ist in der Config deaktiviert.","disabled":true,"alarm":' + BoolJson(Alarm) + '}');
  if CleanTag = '' then
    Exit('{"ok":false,"message":"Kein RFID-Tag uebergeben."}');
  if (SCOConfig.RFIDTagLength > 0) and (Length(CleanTag) < SCOConfig.RFIDTagLength) then
    Exit('{"ok":false,"message":"RFID-Tag unvollstaendig: ' + IntToStr(Length(CleanTag)) + ' / ' + IntToStr(SCOConfig.RFIDTagLength) + ' Zeichen.","alarm":' + BoolJson(Alarm) + '}');
  ConnectDB;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'SELECT FIRST 1 r.TAG, r.STATUS, r.NUMMER, r.GEWICHT, r.PREIS as TAGPREIS, a.VK_BRUTTO as PREIS, a.BEZEICHNUNG, a.ME_BEZ, a.WG, a.MWSTSATZ1, a.MWST_1 ' +
      'FROM TAGINFO r INNER JOIN VARTIKEL a ON r.NUMMER = a.NUMMER ' +
      'WHERE r.TAG STARTING WITH :TAG AND COALESCE(r.STATUS, 0) = 0';
    Q.ParamByName('TAG').AsString := CleanTag;
    Q.Open;
    if Q.IsEmpty then
    begin
      Info := TFDQuery.Create(nil);
      try
        Info.Connection := FB;
        Info.SQL.Text := 'SELECT FIRST 1 TAG, STATUS, NUMMER FROM TAGINFO WHERE TAG STARTING WITH :TAG';
        Info.ParamByName('TAG').AsString := CleanTag;
        Info.Open;
        if Info.IsEmpty then
        begin
          LogTransaction('RFID SCAN FAIL tag=' + CleanTag + ' reason=TAGINFO_NOT_FOUND antenna=' + IntToStr(Antenna));
          Exit('{"ok":false,"message":"RFID-Tag nicht in TAGINFO gefunden.","alarm":' + BoolJson(Alarm) + '}');
        end;
        ActualTag := Info.FieldByName('TAG').AsString;
        TagStatus := Info.FieldByName('STATUS').AsInteger;
        TagNummer := Info.FieldByName('NUMMER').AsInteger;
        if TagStatus <> 0 then
          FailMessage := 'RFID-Tag ist bereits verkauft oder gesperrt. Status=' + IntToStr(TagStatus)
        else
          FailMessage := 'RFID-Tag gefunden, aber Artikel ' + IntToStr(TagNummer) + ' fehlt in VARTIKEL.';
        LogTransaction('RFID SCAN FAIL tag=' + ActualTag + ' status=' + IntToStr(TagStatus) + ' plu=' + IntToStr(TagNummer) + ' reason=' + FailMessage);
        Exit('{"ok":false,"message":"' + JS(FailMessage) + '","tag":"' + JS(ActualTag) + '","status":' + IntToStr(TagStatus) + ',"plu":' + IntToStr(TagNummer) + ',"alarm":' + BoolJson(Alarm) + '}');
      finally
        Info.Free;
      end;
    end;
    ActualTag := Q.FieldByName('TAG').AsString;
    PLU := Q.FieldByName('NUMMER').AsInteger;
    Name := Q.FieldByName('BEZEICHNUNG').AsString;
    UnitName := Q.FieldByName('ME_BEZ').AsString;
    WG := Q.FieldByName('WG').AsInteger;
    Weight := Q.FieldByName('GEWICHT').AsFloat;
    EP := Q.FieldByName('PREIS').AsFloat;
    TagPrice := Q.FieldByName('TAGPREIS').AsFloat;
    if SameText(Trim(UnitName), 'kg') then
    begin
      if Weight <= 0 then Weight := 1;
      GP := EP * Weight;
      if TagPrice > 0 then
        GP := TagPrice;
    end
    else
    begin
      Weight := 1;
      if TagPrice > 0 then
      begin
        EP := TagPrice;
        GP := TagPrice;
      end
      else
        GP := EP;
    end;
    MWST := 7;
    if Q.FindField('MWSTSATZ1') <> nil then
      MWST := StrToIntDef(StringReplace(Q.FieldByName('MWSTSATZ1').AsString, '%', '', [rfReplaceAll]), 0);
    if (MWST <> 7) and (MWST <> 19) and (Q.FindField('MWST_1') <> nil) then
    begin
      if Q.FieldByName('MWST_1').AsInteger = 1 then MWST := 19 else MWST := 7;
    end;
    if MWST <> 19 then MWST := 7;
    if Alarm then
    begin
      LogError('RFID AUSGANGSKONTROLLE TAG=' + CleanTag + ' ANTENNE=' + IntToStr(Antenna) + ' PLU=' + IntToStr(PLU) + ' ARTIKEL=' + Name);
      try
        AddWebUIStatus(4, 0, 0, PLU, ActualTag, Name, 'Ausgangskontrolle - Artikel nicht bezahlt', Weight, EP, GP);
      except
        on E: Exception do LogError('WEBUI STATUS AUSGANGSKONTROLLE ERROR ' + E.Message);
      end;
      try
        AddWebUIMeldung('Ausgangskontrolle', 'Artikel nicht bezahlt: PLU ' + IntToStr(PLU) + ' - ' + Name + ' / Tag ' + ActualTag);
      except
        on E: Exception do LogError('WEBUI MELDUNG AUSGANGSKONTROLLE ERROR ' + E.Message);
      end;
    end
    else
    begin
      try
        AddWebUIStatus(1, 0, 0, PLU, ActualTag, Name, 'Artikel erfasst', Weight, EP, GP);
      except
        on E: Exception do LogError('WEBUI STATUS RFID ERFASST ERROR ' + E.Message);
      end;
    end;
    LogTransaction('RFID SCAN OK tag=' + ActualTag + ' plu=' + IntToStr(PLU) + ' name=' + Name);
    Result :=
      '{"ok":true,' +
      '"type":"rfid",' +
      '"alarm":' + BoolJson(Alarm) + ',' +
      '"alarmSeconds":' + IntToStr(SCOConfig.RFIDExitAlarmSeconds) + ',' +
      '"alarmSystemBeep":' + BoolJson(SCOConfig.RFIDExitAlarmSystemBeep) + ',' +
      '"alarmSound":"' + JS(SCOConfig.RFIDExitAlarmSound) + '",' +
      '"tag":"' + JS(ActualTag) + '",' +
      '"plu":' + IntToStr(PLU) + ',' +
      '"name":"' + JS(Name) + '",' +
      '"unit":"' + JS(UnitName) + '",' +
      '"qty":' + StringReplace(FormatFloat('0.000', Weight), ',', '.', [rfReplaceAll]) + ',' +
      '"ep":' + StringReplace(FormatFloat('0.00', EP), ',', '.', [rfReplaceAll]) + ',' +
      '"gp":' + StringReplace(FormatFloat('0.00', GP), ',', '.', [rfReplaceAll]) + ',' +
      '"wg":' + IntToStr(WG) + ',' +
      '"vatRate":' + IntToStr(MWST) + ',' +
      '"mwst":' + IntToStr(MWST) +
      '}';
  finally
    Q.Free;
  end;
  finally
    RfidScanLock.Leave;
  end;
end;
initialization
  RfidScanLock := TCriticalSection.Create;

finalization
  RfidScanLock.Free;

end.




















