unit SCO_LocalEventService;

interface

uses
  System.SysUtils, System.JSON, FireDAC.Comp.Client;

procedure EnsureLocalEventTable;
procedure AddLocalEvent(const Art, EventLevel, Meldung: string; BonNo, PosNo, PLU: Integer;
  const Artikel, TID: string; Menge, EP, GP: Double; const Quelle: string; Antenne: Integer);
function LocalEventFromJson(const JsonText: string): string;
function LocalEventsJson(FromDate, ToDate: TDateTime): string;

implementation

uses
  SCO_DB, SCO_CONFIG, SCO_Logger, System.SyncObjs;

var
  LocalEventLock: TCriticalSection;

function J(const S: string): string;
begin
  Result := JsonEscape(S);
end;

function N(const V: Double): string;
begin
  Result := StringReplace(FormatFloat('0.00', V), ',', '.', [rfReplaceAll]);
end;

function IField(Q: TFDQuery; const Name: string): Integer;
begin
  Result := 0;
  if (Q.FindField(Name) <> nil) and not Q.FieldByName(Name).IsNull then
    Result := Q.FieldByName(Name).AsInteger;
end;

function FField(Q: TFDQuery; const Name: string): Double;
begin
  Result := 0;
  if (Q.FindField(Name) <> nil) and not Q.FieldByName(Name).IsNull then
    Result := Q.FieldByName(Name).AsFloat;
end;

function SField(Q: TFDQuery; const Name: string): string;
begin
  Result := '';
  if (Q.FindField(Name) <> nil) and not Q.FieldByName(Name).IsNull then
    Result := Q.FieldByName(Name).AsString;
end;

function BoolJson(Value: Boolean): string;
begin
  if Value then Result := 'true' else Result := 'false';
end;

procedure EnsureLocalEventGenerator;
var
  Q: TFDQuery;
  Exists: Boolean;
  MaxId, CurId: Integer;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text := 'select count(*) C from rdb$generators where rdb$generator_name = ''SCO_MELDUNGEN_GEN''';
    Q.Open;
    Exists := IField(Q, 'C') > 0;
    Q.Close;

    if not Exists then
    begin
      try
        FB.ExecSQL('create sequence SCO_MELDUNGEN_GEN');
      except
        // Another running terminal may have created it in the meantime.
      end;
    end;

    Q.SQL.Text := 'select coalesce(max(ID),0) MAXID from SCO_MELDUNGEN';
    Q.Open;
    MaxId := IField(Q, 'MAXID');
    Q.Close;

    Q.SQL.Text := 'select gen_id(SCO_MELDUNGEN_GEN,0) CURID from rdb$database';
    Q.Open;
    CurId := IField(Q, 'CURID');
    Q.Close;

    if CurId < MaxId then
      FB.ExecSQL('set generator SCO_MELDUNGEN_GEN to ' + IntToStr(MaxId));
  finally
    Q.Free;
  end;
end;

function NextLocalEventId: Integer;
var
  Q: TFDQuery;
begin
  Result := 0;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text := 'select gen_id(SCO_MELDUNGEN_GEN,1) ID from rdb$database';
    Q.Open;
    Result := IField(Q, 'ID');
  finally
    Q.Free;
  end;
end;

function TextValue(O: TJSONObject; const Name, Default: string): string;
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

function IntValue(O: TJSONObject; const Name: string; Default: Integer): Integer;
begin
  Result := StrToIntDef(TextValue(O, Name, ''), Default);
end;

function FloatValue(O: TJSONObject; const Name: string; Default: Double): Double;
var
  S: string;
begin
  S := StringReplace(TextValue(O, Name, ''), '.', ',', [rfReplaceAll]);
  Result := StrToFloatDef(S, Default);
end;

procedure EnsureLocalEventTable;
var
  Q: TFDQuery;
  Exists: Boolean;
begin
  ConnectDB;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text := 'select count(*) C from rdb$relations where rdb$relation_name = ''SCO_MELDUNGEN''';
    Q.Open;
    Exists := IField(Q, 'C') > 0;
    Q.Close;
    if Exists then
    begin
      EnsureLocalEventGenerator;
      Exit;
    end;

    FB.ExecSQL(
      'create table SCO_MELDUNGEN (' +
      'ID integer not null primary key,' +
      'DATUHR timestamp,' +
      'DATUM date,' +
      'ZEIT time,' +
      'ART varchar(40),' +
      'EVENT_LEVEL varchar(20),' +
      'MELDUNG varchar(500),' +
      'BONNO integer,' +
      'POSNO integer,' +
      'PLU integer,' +
      'ARTIKEL varchar(160),' +
      'TID varchar(80),' +
      'MENGE double precision,' +
      'EP double precision,' +
      'GP double precision,' +
      'QUELLE varchar(40),' +
      'ANTENNE integer)'
    );
    try
      FB.ExecSQL('create index IDX_SCO_MELDUNGEN_DATUM on SCO_MELDUNGEN (DATUM, ZEIT)');
    except
    end;
    try
      FB.ExecSQL('create index IDX_SCO_MELDUNGEN_ART on SCO_MELDUNGEN (ART, DATUM)');
    except
    end;
    EnsureLocalEventGenerator;
    LogTransaction('LOCAL EVENT TABLE CREATED SCO_MELDUNGEN');
  finally
    Q.Free;
  end;
end;

procedure AddLocalEvent(const Art, EventLevel, Meldung: string; BonNo, PosNo, PLU: Integer;
  const Artikel, TID: string; Menge, EP, GP: Double; const Quelle: string; Antenne: Integer);
var
  Q: TFDQuery;
  NewId: Integer;
begin
  try
    LocalEventLock.Enter;
    try
      EnsureLocalEventTable;
      Q := TFDQuery.Create(nil);
      try
        Q.Connection := FB;
        NewId := NextLocalEventId;

        Q.SQL.Text :=
          'insert into SCO_MELDUNGEN (ID,DATUHR,DATUM,ZEIT,ART,EVENT_LEVEL,MELDUNG,BONNO,POSNO,PLU,ARTIKEL,TID,MENGE,EP,GP,QUELLE,ANTENNE) ' +
          'values (:ID,current_timestamp,:DATUM,:ZEIT,:ART,:EVENT_LEVEL,:MELDUNG,:BONNO,:POSNO,:PLU,:ARTIKEL,:TID,:MENGE,:EP,:GP,:QUELLE,:ANTENNE)';
        Q.ParamByName('ID').AsInteger := NewId;
        Q.ParamByName('DATUM').AsDate := Date;
        Q.ParamByName('ZEIT').AsTime := Time;
        Q.ParamByName('ART').AsString := Copy(Art, 1, 40);
        Q.ParamByName('EVENT_LEVEL').AsString := Copy(EventLevel, 1, 20);
        Q.ParamByName('MELDUNG').AsString := Copy(Meldung, 1, 500);
        Q.ParamByName('BONNO').AsInteger := BonNo;
        Q.ParamByName('POSNO').AsInteger := PosNo;
        Q.ParamByName('PLU').AsInteger := PLU;
        Q.ParamByName('ARTIKEL').AsString := Copy(Artikel, 1, 160);
        Q.ParamByName('TID').AsString := Copy(TID, 1, 80);
        Q.ParamByName('MENGE').AsFloat := Menge;
        Q.ParamByName('EP').AsFloat := EP;
        Q.ParamByName('GP').AsFloat := GP;
        Q.ParamByName('QUELLE').AsString := Copy(Quelle, 1, 40);
        Q.ParamByName('ANTENNE').AsInteger := Antenne;
        Q.ExecSQL;
      finally
        Q.Free;
      end;
    finally
      LocalEventLock.Leave;
    end;
  except
    on E: Exception do
      LogError('LOCAL EVENT WRITE ERROR ' + E.ClassName + ': ' + E.Message);
  end;
end;

function LocalEventFromJson(const JsonText: string): string;
var
  V: TJSONValue;
  O: TJSONObject;
begin
  Result := '{"ok":false,"message":"Meldung konnte nicht geschrieben werden."}';
  V := TJSONObject.ParseJSONValue(JsonText);
  try
    if not (V is TJSONObject) then Exit;
    O := TJSONObject(V);
    AddLocalEvent(
      TextValue(O, 'art', 'MELDUNG'),
      TextValue(O, 'level', 'info'),
      TextValue(O, 'message', ''),
      IntValue(O, 'bon', 0),
      IntValue(O, 'pos', 0),
      IntValue(O, 'plu', 0),
      TextValue(O, 'name', ''),
      TextValue(O, 'tag', ''),
      FloatValue(O, 'qty', 0),
      FloatValue(O, 'ep', 0),
      FloatValue(O, 'gp', 0),
      TextValue(O, 'source', 'sco'),
      IntValue(O, 'antenna', 0)
    );
    Result := '{"ok":true,"message":"Meldung gespeichert."}';
  except
    on E: Exception do
      Result := '{"ok":false,"message":"Meldung Fehler: ' + J(E.Message) + '"}';
  end;
  V.Free;
end;

function LocalEventsJson(FromDate, ToDate: TDateTime): string;
var
  Q: TFDQuery;
  Messages, Products: string;
  First: Boolean;
  Captured, Removed, Purchased, ExitAlarms, Missing: Integer;
begin
  Result := '{"available":false,"captured":0,"removed":0,"purchased":0,"exitAlarms":0,"products":[],"messages":[]}';
  try
    EnsureLocalEventTable;
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := FB;
      Captured := 0; Removed := 0; Purchased := 0; ExitAlarms := 0;
      Q.SQL.Text := 'select ART,count(*) ANZAHL from SCO_MELDUNGEN where DATUM between :FROMDATE and :TODATE group by ART';
      Q.ParamByName('FROMDATE').AsDate := FromDate;
      Q.ParamByName('TODATE').AsDate := ToDate;
      Q.Open;
      while not Q.Eof do
      begin
        if SameText(SField(Q,'ART'), 'RFID_ERFASST') then Captured := IField(Q,'ANZAHL')
        else if SameText(SField(Q,'ART'), 'RFID_ENTFERNT') then Removed := IField(Q,'ANZAHL')
        else if SameText(SField(Q,'ART'), 'ARTIKEL_GEKAUFT') then Purchased := IField(Q,'ANZAHL')
        else if SameText(SField(Q,'ART'), 'AUSGANGSKONTROLLE') then ExitAlarms := IField(Q,'ANZAHL');
        Q.Next;
      end;
      Q.Close;

      Q.SQL.Text := 'select PLU,max(ARTIKEL) ARTIKEL,' +
        'sum(case when ART=''RFID_ERFASST'' then 1 else 0 end) ERFASST,' +
        'sum(case when ART=''RFID_ENTFERNT'' then 1 else 0 end) ENTFERNT,' +
        'sum(case when ART=''ARTIKEL_GEKAUFT'' then 1 else 0 end) GEKAUFT,' +
        'sum(case when ART=''AUSGANGSKONTROLLE'' then 1 else 0 end) AUSGANG ' +
        'from SCO_MELDUNGEN where DATUM between :FROMDATE and :TODATE and coalesce(PLU,0)<>0 ' +
        'group by PLU order by AUSGANG desc, ERFASST desc, GEKAUFT desc';
      Q.ParamByName('FROMDATE').AsDate := FromDate;
      Q.ParamByName('TODATE').AsDate := ToDate;
      Q.Open;
      Products := '['; First := True;
      while not Q.Eof do
      begin
        if not First then Products := Products + ',';
        Missing := IField(Q,'ERFASST') - IField(Q,'GEKAUFT') - IField(Q,'ENTFERNT');
        if Missing < 0 then Missing := 0;
        Products := Products + '{"plu":' + IntToStr(IField(Q,'PLU')) + ',"name":"' + J(SField(Q,'ARTIKEL')) +
          '","captured":' + IntToStr(IField(Q,'ERFASST')) + ',"removed":' + IntToStr(IField(Q,'ENTFERNT')) +
          ',"purchased":' + IntToStr(IField(Q,'GEKAUFT')) + ',"exitAlarms":' + IntToStr(IField(Q,'AUSGANG')) +
          ',"notPurchased":' + IntToStr(Missing) + '}';
        First := False;
        Q.Next;
      end;
      Products := Products + ']';
      Q.Close;

      Q.SQL.Text := 'select first 500 DATUM,ZEIT,ART,EVENT_LEVEL,MELDUNG,BONNO,PLU,ARTIKEL,TID,QUELLE,ANTENNE ' +
        'from SCO_MELDUNGEN where DATUM between :FROMDATE and :TODATE order by DATUHR desc, ID desc';
      Q.ParamByName('FROMDATE').AsDate := FromDate;
      Q.ParamByName('TODATE').AsDate := ToDate;
      Q.Open;
      Messages := '['; First := True;
      while not Q.Eof do
      begin
        if not First then Messages := Messages + ',';
        Messages := Messages + '{"date":"' + FormatDateTime('dd.mm.yyyy', Q.FieldByName('DATUM').AsDateTime) +
          '","time":"' + FormatDateTime('hh:nn:ss', Q.FieldByName('ZEIT').AsDateTime) +
          '","type":"' + J(SField(Q,'ART')) + '","level":"' + J(SField(Q,'EVENT_LEVEL')) +
          '","message":"' + J(SField(Q,'MELDUNG')) + '","bon":' + IntToStr(IField(Q,'BONNO')) +
          ',"plu":' + IntToStr(IField(Q,'PLU')) + ',"name":"' + J(SField(Q,'ARTIKEL')) +
          '","tag":"' + J(SField(Q,'TID')) + '","source":"' + J(SField(Q,'QUELLE')) +
          '","antenna":' + IntToStr(IField(Q,'ANTENNE')) + '}';
        First := False;
        Q.Next;
      end;
      Messages := Messages + ']';

      Result := '{"available":true,"captured":' + IntToStr(Captured) + ',"removed":' + IntToStr(Removed) +
        ',"purchased":' + IntToStr(Purchased) + ',"exitAlarms":' + IntToStr(ExitAlarms) +
        ',"products":' + Products + ',"messages":' + Messages + '}';
    finally
      Q.Free;
    end;
  except
    on E: Exception do
    begin
      LogError('LOCAL EVENTS JSON ERROR ' + E.ClassName + ': ' + E.Message);
      Result := '{"available":false,"message":"' + J(E.Message) + '","captured":0,"removed":0,"purchased":0,"exitAlarms":0,"products":[],"messages":[]}';
    end;
  end;
end;

initialization
  LocalEventLock := TCriticalSection.Create;

finalization
  LocalEventLock.Free;

end.
