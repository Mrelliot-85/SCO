unit SCO_StatisticsService;

interface

uses
  System.SysUtils;

function StatisticsJson(Days: Integer; const FromText, ToText: string): string;
function StatisticsMarkSentJson(const FromText, ToText: string): string;

implementation

uses
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Def,
  FireDAC.Stan.Intf,
  FireDAC.Phys,
  FireDAC.Phys.MySQL,
  FireDAC.Phys.MySQLDef,
  SCO_DB,
  SCO_CONFIG,
  SCO_Logger;

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

function ParseIsoDate(const S: string; DefaultValue: TDateTime): TDateTime;
var
  Y, M, D: Integer;
begin
  Result := DefaultValue;
  if Length(Trim(S)) <> 10 then Exit;
  Y := StrToIntDef(Copy(S, 1, 4), 0);
  M := StrToIntDef(Copy(S, 6, 2), 0);
  D := StrToIntDef(Copy(S, 9, 2), 0);
  try
    Result := EncodeDate(Y, M, D);
  except
    Result := DefaultValue;
  end;
end;

procedure ResolveRange(Days: Integer; const FromText, ToText: string;
  out FromDate, ToDate: TDateTime);
begin
  if Days < 1 then Days := 30;
  if Days > 730 then Days := 730;
  ToDate := ParseIsoDate(ToText, Date);
  FromDate := ParseIsoDate(FromText, ToDate - Days + 1);
  if FromDate > ToDate then
    FromDate := ToDate;
  if ToDate - FromDate > 730 then
    FromDate := ToDate - 730;
end;

procedure SetRange(Q: TFDQuery; FromDate, ToDate: TDateTime);
begin
  if Q.Params.FindParam('FROMDATE') <> nil then
    Q.ParamByName('FROMDATE').AsDateTime := FromDate;
  if Q.Params.FindParam('TODATE') <> nil then
    Q.ParamByName('TODATE').AsDateTime := ToDate;
end;

function ProductRows(FromDate, ToDate: TDateTime; Descending: Boolean): string;
var
  Q: TFDQuery;
  First: Boolean;
  Direction: string;
begin
  Result := '[]';
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    if Descending then Direction := 'desc' else Direction := 'asc';
    Q.SQL.Text :=
      'select first 10 u.ARTNR, max(v.BEZEICHNUNG) as NAME, ' +
      'sum(u.MENGE) as MENGE, sum(u.GP) as UMSATZ, count(*) as POSITIONEN ' +
      'from UC3_UMSATZ u left join VARTIKEL v on v.NUMMER = u.ARTNR and v.NL_KEY = :NLKEY ' +
      'where u.DATUM between :FROMDATE and :TODATE and coalesce(u.STORNO,0)=0 ' +
      'and coalesce(u.ZEILENSTORNO,0)=0 group by u.ARTNR ' +
      'having sum(u.GP) > 0 order by 4 ' + Direction;
    SetRange(Q, FromDate, ToDate);
    Q.ParamByName('NLKEY').AsInteger := SCOConfig.NLKey;
    Q.Open;
    Result := '[';
    First := True;
    while not Q.Eof do
    begin
      if not First then Result := Result + ',';
      Result := Result + '{"plu":"' + J(SField(Q,'ARTNR')) +
        '","name":"' + J(SField(Q,'NAME')) +
        '","qty":' + N(FField(Q,'MENGE')) +
        ',"revenue":' + N(FField(Q,'UMSATZ')) +
        ',"positions":' + IntToStr(IField(Q,'POSITIONEN')) + '}';
      First := False;
      Q.Next;
    end;
    Result := Result + ']';
  except
    on E: Exception do
    begin
      LogError('STATISTICS PRODUCTS: ' + E.Message);
      Result := '[]';
    end;
  end;
  Q.Free;
end;

function SalesRows(FromDate, ToDate: TDateTime): string;
var Q: TFDQuery; First: Boolean;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text := 'select first 250 u.ARTNR,max(v.BEZEICHNUNG) NAME,max(u.ME) ME,' +
      'sum(u.MENGE) MENGE,sum(u.GP) UMSATZ,count(*) POSITIONEN from UC3_UMSATZ u ' +
      'left join VARTIKEL v on v.NUMMER=u.ARTNR and v.NL_KEY=:NLKEY ' +
      'where u.DATUM between :FROMDATE and :TODATE and coalesce(u.STORNO,0)=0 ' +
      'and coalesce(u.ZEILENSTORNO,0)=0 group by u.ARTNR order by 5 desc';
    SetRange(Q,FromDate,ToDate); Q.ParamByName('NLKEY').AsInteger:=SCOConfig.NLKey; Q.Open;
    Result:='['; First:=True;
    while not Q.Eof do begin
      if not First then Result:=Result+',';
      Result:=Result+'{"plu":"'+J(SField(Q,'ARTNR'))+'","name":"'+J(SField(Q,'NAME'))+
        '","unit":"'+J(SField(Q,'ME'))+'","qty":'+N(FField(Q,'MENGE'))+
        ',"revenue":'+N(FField(Q,'UMSATZ'))+',"positions":'+IntToStr(IField(Q,'POSITIONEN'))+'}';
      First:=False; Q.Next;
    end;
    Result:=Result+']';
  except on E:Exception do begin LogError('STATISTICS SALES: '+E.Message); Result:='[]'; end; end;
  Q.Free;
end;
function JournalRows(FromDate, ToDate: TDateTime): string;
var Q:TFDQuery; FirstBon,FirstItem,OpenBon:Boolean; Key,LastKey:string;
begin
  Q:=TFDQuery.Create(nil);
  try
    Q.Connection:=FB;
    Q.SQL.Text:='select first 750 u.FILIAL_ID,u.GERAET,u.DATUM,u.BONNO,u.POSNO,u.ZEIT,'+
      'u.ARTNR,u.MWST,u.EP,u.GP,u.ME,u.MENGE,u.TENDERNAME,v.BEZEICHNUNG NAME,'+
      '(select count(*) from UC3_UMSATZ c where c.FILIAL_ID=u.FILIAL_ID and c.GERAET=u.GERAET and c.DATUM=u.DATUM and c.BONNO=u.BONNO and coalesce(c.STORNO,0)=0 and coalesce(c.ZEILENSTORNO,0)=0) BON_POS,'+
      '(select sum(c.GP) from UC3_UMSATZ c where c.FILIAL_ID=u.FILIAL_ID and c.GERAET=u.GERAET and c.DATUM=u.DATUM and c.BONNO=u.BONNO and coalesce(c.STORNO,0)=0 and coalesce(c.ZEILENSTORNO,0)=0) BON_TOTAL '+
      'from UC3_UMSATZ u left join VARTIKEL v on v.NUMMER=u.ARTNR and v.NL_KEY=:NLKEY '+
      'where u.DATUM between :FROMDATE and :TODATE and coalesce(u.STORNO,0)=0 and coalesce(u.ZEILENSTORNO,0)=0 '+
      'order by u.DATUM desc,u.BONNO desc,u.POSNO';
    SetRange(Q,FromDate,ToDate); Q.ParamByName('NLKEY').AsInteger:=SCOConfig.NLKey; Q.Open;
    Result:='['; FirstBon:=True; FirstItem:=True; OpenBon:=False; LastKey:='';
    while not Q.Eof do begin
      Key:=FormatDateTime('yyyymmdd',Q.FieldByName('DATUM').AsDateTime)+'|'+SField(Q,'FILIAL_ID')+'|'+SField(Q,'GERAET')+'|'+SField(Q,'BONNO');
      if Key<>LastKey then begin
        if OpenBon then Result:=Result+']}';
        if not FirstBon then Result:=Result+',';
        Result:=Result+'{"date":"'+FormatDateTime('dd.mm.yyyy',Q.FieldByName('DATUM').AsDateTime)+
          '","time":"'+FormatDateTime('hh:nn:ss',Q.FieldByName('ZEIT').AsDateTime)+
          '","branch":'+IntToStr(IField(Q,'FILIAL_ID'))+',"register":'+IntToStr(IField(Q,'GERAET'))+
          ',"bon":'+IntToStr(IField(Q,'BONNO'))+',"payment":"'+J(SField(Q,'TENDERNAME'))+
          '","positions":'+IntToStr(IField(Q,'BON_POS'))+',"total":'+N(FField(Q,'BON_TOTAL'))+',"items":[';
        FirstBon:=False; FirstItem:=True; OpenBon:=True; LastKey:=Key;
      end;
      if not FirstItem then Result:=Result+',';
      Result:=Result+'{"pos":'+IntToStr(IField(Q,'POSNO'))+',"plu":"'+J(SField(Q,'ARTNR'))+
        '","name":"'+J(SField(Q,'NAME'))+'","qty":'+N(FField(Q,'MENGE'))+
        ',"unit":"'+J(SField(Q,'ME'))+'","ep":'+N(FField(Q,'EP'))+
        ',"total":'+N(FField(Q,'GP'))+',"vat":'+N(FField(Q,'MWST'))+'}';
      FirstItem:=False; Q.Next;
    end;
    if OpenBon then Result:=Result+']}'; Result:=Result+']';
  except on E:Exception do begin LogError('STATISTICS JOURNAL: '+E.Message); Result:='[]'; end; end;
  Q.Free;
end;
function WebUIRows(FromDate, ToDate: TDateTime): string;
var C:TFDConnection; Q:TFDQuery; Products,Messages:string; First:Boolean; Captured,Removed,Purchased,Missing:Integer;
begin
  Result:='{"available":false,"captured":0,"removed":0,"purchased":0,"products":[],"messages":[]}';
  SCOConfig.Load;
  if not SCOConfig.WebUIAktiv then Exit;
  if (Trim(SCOConfig.WebUIHost)='') or (Trim(SCOConfig.WebUIDatabase)='') then Exit;
  C:=TFDConnection.Create(nil); Q:=TFDQuery.Create(nil);
  try
    C.LoginPrompt:=False; C.Params.DriverID:='MySQL';
    C.Params.Values['Server']:=SCOConfig.WebUIHost; C.Params.Values['Port']:=IntToStr(SCOConfig.WebUIPort);
    C.Params.Values['Database']:=SCOConfig.WebUIDatabase; C.Params.Values['User_Name']:=SCOConfig.WebUIUser;
    C.Params.Values['Password']:=SCOConfig.WebUIPassword; C.ResourceOptions.AutoReconnect:=True; C.Connected:=True; Q.Connection:=C;
    Q.SQL.Text:='select STATUS,count(*) ANZAHL from Transaktionen where KUNDE=:KUNDE and DATUM between :FROMDATE and :TODATE and coalesce(TID,'''')<>'''' group by STATUS';
    Q.ParamByName('KUNDE').AsInteger:=SCOConfig.KundenNr; SetRange(Q,FromDate,ToDate); Q.Open;
    Captured:=0; Removed:=0; Purchased:=0;
    while not Q.Eof do begin case IField(Q,'STATUS') of 1:Captured:=IField(Q,'ANZAHL'); 2:Removed:=IField(Q,'ANZAHL'); 3:Purchased:=IField(Q,'ANZAHL'); end; Q.Next; end; Q.Close;
    Q.SQL.Text:='select PLU,max(ARTIKEL) ARTIKEL,count(distinct case when STATUS=1 then TID end) ERFASST,'+
      'count(distinct case when STATUS=2 then TID end) ENTFERNT,count(distinct case when STATUS=3 then TID end) GEKAUFT '+
      'from Transaktionen where KUNDE=:KUNDE and DATUM between :FROMDATE and :TODATE and coalesce(TID,'''')<>'''' group by PLU order by ERFASST desc,GEKAUFT desc';
    Q.ParamByName('KUNDE').AsInteger:=SCOConfig.KundenNr; SetRange(Q,FromDate,ToDate); Q.Open;
    Products:='['; First:=True;
    while not Q.Eof do begin
      if not First then Products:=Products+','; Missing:=IField(Q,'ERFASST')-IField(Q,'GEKAUFT'); if Missing<0 then Missing:=0;
      Products:=Products+'{"plu":'+IntToStr(IField(Q,'PLU'))+',"name":"'+J(SField(Q,'ARTIKEL'))+
        '","captured":'+IntToStr(IField(Q,'ERFASST'))+',"removed":'+IntToStr(IField(Q,'ENTFERNT'))+
        ',"purchased":'+IntToStr(IField(Q,'GEKAUFT'))+',"notPurchased":'+IntToStr(Missing)+'}'; First:=False; Q.Next;
    end; Products:=Products+']'; Q.Close;
    Q.SQL.Text:='select ART,MELDUNG,DATUM,UHRZEIT from `Status` where KUNDE=:KUNDE and DATUM between :FROMDATE and :TODATE order by DATUM desc,UHRZEIT desc limit 200';
    Q.ParamByName('KUNDE').AsInteger:=SCOConfig.KundenNr; SetRange(Q,FromDate,ToDate); Q.Open;
    Messages:='['; First:=True;
    while not Q.Eof do begin
      if not First then Messages:=Messages+',';
      Messages:=Messages+'{"date":"'+FormatDateTime('dd.mm.yyyy',Q.FieldByName('DATUM').AsDateTime)+
        '","time":"'+FormatDateTime('hh:nn:ss',Q.FieldByName('UHRZEIT').AsDateTime)+
        '","type":"'+J(SField(Q,'ART'))+'","message":"'+J(SField(Q,'MELDUNG'))+'"}'; First:=False; Q.Next;
    end; Messages:=Messages+']';
    Result:='{"available":true,"captured":'+IntToStr(Captured)+',"removed":'+IntToStr(Removed)+
      ',"purchased":'+IntToStr(Purchased)+',"products":'+Products+',"messages":'+Messages+'}';
  except on E:Exception do begin LogError('STATISTICS WEBUI: '+E.Message); Result:='{"available":false,"message":"'+J(E.Message)+'","captured":0,"removed":0,"purchased":0,"products":[],"messages":[]}'; end; end;
  Q.Free; C.Free;
end;
function StatisticsJson(Days: Integer; const FromText, ToText: string): string;
var
  Q: TFDQuery;
  FromDate, ToDate: TDateTime;
  KPI, Payments, Hours, Weekdays, Daily, Journal, Taxes, SendState: string;
  First: Boolean;
begin
  ResolveRange(Days, FromText, ToText, FromDate, ToDate);
  Days := Trunc(ToDate - FromDate) + 1;
  KPI := '{"receipts":0,"revenue":0,"avgReceipt":0,"avgPositions":0,"positions":0}';
  Payments := '[]';
  Hours := '[]';
  Weekdays := '[]';
  Daily := '[]';
  Journal := '[]';
  Taxes := '[]';
  SendState := '{"rows":0,"sent":0,"open":0}';

  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;

    Q.SQL.Text :=
      'select count(*) as BONS, coalesce(sum(x.BON_TOTAL),0) as UMSATZ, ' +
      'coalesce(avg(x.BON_TOTAL),0) as BON_DURCHSCHNITT, ' +
      'coalesce(avg(x.POS_COUNT),0) as POS_DURCHSCHNITT, ' +
      'coalesce(sum(x.POS_COUNT),0) as POSITIONEN from (' +
      'select FILIAL_ID, GERAET, DATUM, BONNO, sum(GP) as BON_TOTAL, count(*) as POS_COUNT ' +
      'from UC3_UMSATZ where DATUM between :FROMDATE and :TODATE and coalesce(STORNO,0)=0 ' +
      'and coalesce(ZEILENSTORNO,0)=0 group by FILIAL_ID, GERAET, DATUM, BONNO) x';
    SetRange(Q, FromDate, ToDate);
    Q.Open;
    KPI := '{"receipts":' + IntToStr(IField(Q,'BONS')) +
      ',"revenue":' + N(FField(Q,'UMSATZ')) +
      ',"avgReceipt":' + N(FField(Q,'BON_DURCHSCHNITT')) +
      ',"avgPositions":' + N(FField(Q,'POS_DURCHSCHNITT')) +
      ',"positions":' + IntToStr(IField(Q,'POSITIONEN')) + '}';
    Q.Close;

    Q.SQL.Text :=
      'select coalesce(TENDERNAME,''Unbekannt'') as NAME, sum(GP) as UMSATZ ' +
      'from UC3_UMSATZ where DATUM between :FROMDATE and :TODATE and coalesce(STORNO,0)=0 ' +
      'and coalesce(ZEILENSTORNO,0)=0 group by TENDERNAME order by 2 desc';
    SetRange(Q, FromDate, ToDate);
    Q.Open;
    Payments := '['; First := True;
    while not Q.Eof do
    begin
      if not First then Payments := Payments + ',';
      Payments := Payments + '{"name":"' + J(SField(Q,'NAME')) +
        '","value":' + N(FField(Q,'UMSATZ')) + '}';
      First := False; Q.Next;
    end;
    Payments := Payments + ']';
    Q.Close;

    Q.SQL.Text :=
      'select MWST, sum(GP) as BRUTTO, sum(GP / (1 + MWST / 100)) as NETTO ' +
      'from UC3_UMSATZ where DATUM between :FROMDATE and :TODATE and coalesce(STORNO,0)=0 ' +
      'and coalesce(ZEILENSTORNO,0)=0 group by MWST order by MWST';
    SetRange(Q, FromDate, ToDate);
    Q.Open;
    Taxes := '['; First := True;
    while not Q.Eof do
    begin
      if not First then Taxes := Taxes + ',';
      Taxes := Taxes + '{"rate":' + N(FField(Q,'MWST')) +
        ',"gross":' + N(FField(Q,'BRUTTO')) +
        ',"net":' + N(FField(Q,'NETTO')) +
        ',"tax":' + N(FField(Q,'BRUTTO') - FField(Q,'NETTO')) + '}';
      First := False; Q.Next;
    end;
    Taxes := Taxes + ']';
    Q.Close;

    Q.SQL.Text :=
      'select count(*) as ROWS_TOTAL, ' +
      'sum(case when coalesce(GESENDET,''F'')=''T'' then 1 else 0 end) as SENT_ROWS ' +
      'from UC3_UMSATZ where DATUM between :FROMDATE and :TODATE and coalesce(STORNO,0)=0 ' +
      'and coalesce(ZEILENSTORNO,0)=0';
    SetRange(Q, FromDate, ToDate);
    Q.Open;
    SendState := '{"rows":' + IntToStr(IField(Q,'ROWS_TOTAL')) +
      ',"sent":' + IntToStr(IField(Q,'SENT_ROWS')) +
      ',"open":' + IntToStr(IField(Q,'ROWS_TOTAL') - IField(Q,'SENT_ROWS')) + '}';
    Q.Close;

    Q.SQL.Text :=
      'select STUNDE, count(*) as BONS, sum(BON_TOTAL) as UMSATZ from (' +
      'select FILIAL_ID, GERAET, DATUM, BONNO, max(STUNDE) as STUNDE, sum(GP) as BON_TOTAL ' +
      'from UC3_UMSATZ where DATUM between :FROMDATE and :TODATE and coalesce(STORNO,0)=0 ' +
      'and coalesce(ZEILENSTORNO,0)=0 group by FILIAL_ID, GERAET, DATUM, BONNO) x ' +
      'group by STUNDE order by STUNDE';
    SetRange(Q, FromDate, ToDate);
    Q.Open;
    Hours := '['; First := True;
    while not Q.Eof do
    begin
      if not First then Hours := Hours + ',';
      Hours := Hours + '{"hour":' + IntToStr(IField(Q,'STUNDE')) +
        ',"receipts":' + IntToStr(IField(Q,'BONS')) +
        ',"revenue":' + N(FField(Q,'UMSATZ')) + '}';
      First := False; Q.Next;
    end;
    Hours := Hours + ']';
    Q.Close;

    Q.SQL.Text :=
      'select WT, count(*) as BONS, sum(BON_TOTAL) as UMSATZ from (' +
      'select FILIAL_ID, GERAET, DATUM, BONNO, max(WT) as WT, sum(GP) as BON_TOTAL ' +
      'from UC3_UMSATZ where DATUM between :FROMDATE and :TODATE and coalesce(STORNO,0)=0 ' +
      'and coalesce(ZEILENSTORNO,0)=0 group by FILIAL_ID, GERAET, DATUM, BONNO) x ' +
      'group by WT order by WT';
    SetRange(Q, FromDate, ToDate);
    Q.Open;
    Weekdays := '['; First := True;
    while not Q.Eof do
    begin
      if not First then Weekdays := Weekdays + ',';
      Weekdays := Weekdays + '{"day":' + IntToStr(IField(Q,'WT')) +
        ',"receipts":' + IntToStr(IField(Q,'BONS')) +
        ',"revenue":' + N(FField(Q,'UMSATZ')) + '}';
      First := False; Q.Next;
    end;
    Weekdays := Weekdays + ']';
    Q.Close;

    Q.SQL.Text :=
      'select DATUM, count(distinct BONNO) as BONS, sum(GP) as UMSATZ, ' +
      'sum(GP / (1 + MWST / 100)) as NETTO from UC3_UMSATZ ' +
      'where DATUM between :FROMDATE and :TODATE and coalesce(STORNO,0)=0 ' +
      'and coalesce(ZEILENSTORNO,0)=0 group by DATUM order by DATUM';
    SetRange(Q, FromDate, ToDate);
    Q.Open;
    Daily := '['; First := True;
    while not Q.Eof do
    begin
      if not First then Daily := Daily + ',';
      Daily := Daily + '{"date":"' + FormatDateTime('yyyy-mm-dd', Q.FieldByName('DATUM').AsDateTime) +
        '","receipts":' + IntToStr(IField(Q,'BONS')) +
        ',"net":' + N(FField(Q,'NETTO')) +
        ',"tax":' + N(FField(Q,'UMSATZ') - FField(Q,'NETTO')) +
        ',"value":' + N(FField(Q,'UMSATZ')) + '}';
      First := False; Q.Next;
    end;
    Daily := Daily + ']';
    Q.Close;

    Journal := JournalRows(FromDate, ToDate);

    Result := '{"ok":true,"days":' + IntToStr(Days) +
      ',"from":"' + FormatDateTime('yyyy-mm-dd', FromDate) +
      '","to":"' + FormatDateTime('yyyy-mm-dd', ToDate) +
      '","kpi":' + KPI +
      ',"top":' + ProductRows(FromDate, ToDate, True) +
      ',"bottom":' + ProductRows(FromDate, ToDate, False) +
      ',"sales":' + SalesRows(FromDate, ToDate) +
      ',"webui":' + WebUIRows(FromDate, ToDate) +
      ',"payments":' + Payments +
      ',"taxes":' + Taxes +
      ',"sendState":' + SendState +
      ',"hours":' + Hours +
      ',"weekdays":' + Weekdays +
      ',"daily":' + Daily +
      ',"journal":' + Journal + '}';
  except
    on E: Exception do
    begin
      LogError('STATISTICS ERROR: ' + E.Message);
      Result := '{"ok":false,"message":"' + J(E.Message) + '"}';
    end;
  end;
  Q.Free;
end;

function StatisticsMarkSentJson(const FromText, ToText: string): string;
var
  Q: TFDQuery;
  FromDate, ToDate: TDateTime;
  Count: Integer;
begin
  ResolveRange(1, FromText, ToText, FromDate, ToDate);
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'update UC3_UMSATZ set GESENDET=''T'', DATUM_GESENDET=current_timestamp ' +
      'where DATUM between :FROMDATE and :TODATE and coalesce(STORNO,0)=0 ' +
      'and coalesce(ZEILENSTORNO,0)=0 and coalesce(GESENDET,''F'')<>''T''';
    SetRange(Q, FromDate, ToDate);
    Q.ExecSQL;
    Count := Q.RowsAffected;
    LogTransaction('STATISTICS REPORT BOOKED from=' +
      FormatDateTime('yyyy-mm-dd', FromDate) + ' to=' +
      FormatDateTime('yyyy-mm-dd', ToDate) + ' rows=' + IntToStr(Count));
    Result := '{"ok":true,"rows":' + IntToStr(Count) +
      ',"message":"Zeitraum wurde als gesendet verbucht."}';
  except
    on E: Exception do
    begin
      LogError('STATISTICS BOOK ERROR: ' + E.Message);
      Result := '{"ok":false,"message":"' + J(E.Message) + '"}';
    end;
  end;
  Q.Free;
end;

end.
