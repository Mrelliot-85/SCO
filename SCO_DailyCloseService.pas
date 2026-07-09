unit SCO_DailyCloseService;

interface

uses System.SysUtils;

function DailyCloseRunJson(ACloseDate: TDateTime; Automatic: Boolean): string;
function DailyCloseListJson: string;
function DailyCloseReceiptJson(ID: Integer): string;
function DailyClosePrintJson(ID: Integer): string;
function DailyCloseExists(ACloseDate: TDateTime): Boolean;
procedure CheckScheduledDailyClose;

implementation

uses
  Winapi.Windows, Winapi.ShellAPI, System.Classes, System.IOUtils,
  System.Win.Registry, System.SyncObjs, System.StrUtils, Data.DB, FireDAC.Comp.Client,
  SCO_CONFIG, SCO_DB, SCO_CashLogyService, SCO_ZVTUtils, SCO_Logger, SCO_ReceiptService;

var CloseLock: TCriticalSection;

function J(const S:string):string;
begin
  Result:=JsonEscape(S);
end;

function N(V:Double):string;
begin
  Result:=StringReplace(FormatFloat('0.00',V),',','.',[rfReplaceAll]);
end;

procedure EnsureTable;
var Q:TFDQuery;
begin
  ConnectDB;
  Q:=TFDQuery.Create(nil);
  try
    Q.Connection:=FB;
    Q.SQL.Text:='select count(*) ANZAHL from RDB$RELATIONS where RDB$RELATION_NAME=''SCO_KASSENABSCHLUSS''';
    Q.Open;
    if Q.FieldByName('ANZAHL').AsInteger=0 then begin
      Q.Close;
      Q.SQL.Text:=
        'create table SCO_KASSENABSCHLUSS ('+
        'ID integer not null, FILIAL_ID integer, GERAET integer, ABSCHLUSSDATUM date, ABSCHLUSSZEIT timestamp,'+
        'STATUS varchar(20), AUTOMATISCH smallint, BONS integer, POSITIONEN integer,'+
        'UMSATZ_GESAMT double precision, BRUTTO_7 double precision, NETTO_7 double precision, MWST_7 double precision,'+
        'BRUTTO_19 double precision, NETTO_19 double precision, MWST_19 double precision,'+
        'UMSATZ_BAR double precision, UMSATZ_EC double precision,'+
        'ZVT_AKTIV smallint, ZVT_OK smallint, ZVT_ERGEBNIS integer, ZVT_TEXT blob sub_type text, ZVT_DATEN blob sub_type text,'+
        'CASHLOGY_AKTIV smallint, CASHLOGY_OK smallint, CASHLOGY_BESTAND double precision, CASHLOGY_STORE double precision,'+
        'CASHLOGY_STACKER double precision, CASHLOGY_TEXT blob sub_type text,'+
        'FEHLER blob sub_type text, ERSTELLT timestamp, constraint PK_SCO_KASSENABSCHLUSS primary key (ID))';
      Q.ExecSQL;
      Q.SQL.Text:='create unique index UQ_SCO_KASSENABSCHLUSS on SCO_KASSENABSCHLUSS (FILIAL_ID,GERAET,ABSCHLUSSDATUM)';
      Q.ExecSQL;
      LogTransaction('KASSENABSCHLUSS TABLE CREATED');
    end;
  finally Q.Free; end;
end;

function DailyCloseExists(ACloseDate:TDateTime):Boolean;
var Q:TFDQuery;
begin
  Result:=False;
  EnsureTable;
  Q:=TFDQuery.Create(nil);
  try
    Q.Connection:=FB;
    Q.SQL.Text:='select count(*) ANZAHL from SCO_KASSENABSCHLUSS where FILIAL_ID=:F and GERAET=:G and ABSCHLUSSDATUM=:D';
    Q.ParamByName('F').AsInteger:=StrToIntDef(SCOConfig.BonjournalFilialId,SCOConfig.KundenNr);
    Q.ParamByName('G').AsInteger:=SCOConfig.ZVT_Kasse;
    Q.ParamByName('D').AsDate:=ACloseDate;
    Q.Open; Result:=Q.FieldByName('ANZAHL').AsInteger>0;
  finally Q.Free; end;
end;

procedure ReadTotals(ACloseDate:TDateTime; out Bons,Positions:Integer; out Total,B7,N7,T7,B19,N19,T19,Bar,EC:Double);
var Q:TFDQuery; Rate:Integer;
begin
  Bons:=0; Positions:=0; Total:=0; B7:=0; N7:=0; T7:=0; B19:=0; N19:=0; T19:=0; Bar:=0; EC:=0;
  Q:=TFDQuery.Create(nil);
  try
    Q.Connection:=FB;
    Q.SQL.Text:='select count(distinct BONNO) BONS,count(*) POSITIONEN,coalesce(sum(GP),0) UMSATZ from UC3_UMSATZ '+
      'where DATUM=:D and coalesce(STORNO,0)=0 and coalesce(ZEILENSTORNO,0)=0';
    Q.ParamByName('D').AsDate:=ACloseDate; Q.Open;
    Bons:=Q.FieldByName('BONS').AsInteger; Positions:=Q.FieldByName('POSITIONEN').AsInteger; Total:=Q.FieldByName('UMSATZ').AsFloat; Q.Close;
    Q.SQL.Text:='select MWST,coalesce(sum(GP),0) BRUTTO,coalesce(sum(GP/(1+MWST/100)),0) NETTO from UC3_UMSATZ '+
      'where DATUM=:D and coalesce(STORNO,0)=0 and coalesce(ZEILENSTORNO,0)=0 group by MWST';
    Q.ParamByName('D').AsDate:=ACloseDate; Q.Open;
    while not Q.Eof do begin
      Rate:=Round(Q.FieldByName('MWST').AsFloat);
      if Rate=19 then begin B19:=Q.FieldByName('BRUTTO').AsFloat; N19:=Q.FieldByName('NETTO').AsFloat; T19:=B19-N19; end
      else if Rate=7 then begin B7:=Q.FieldByName('BRUTTO').AsFloat; N7:=Q.FieldByName('NETTO').AsFloat; T7:=B7-N7; end;
      Q.Next;
    end; Q.Close;
    Q.SQL.Text:='select coalesce(TENDERNAME,'''') ZAHLART,coalesce(sum(GP),0) UMSATZ from UC3_UMSATZ '+
      'where DATUM=:D and coalesce(STORNO,0)=0 and coalesce(ZEILENSTORNO,0)=0 group by TENDERNAME';
    Q.ParamByName('D').AsDate:=ACloseDate; Q.Open;
    while not Q.Eof do begin
      if SameText(Q.FieldByName('ZAHLART').AsString,'BAR') then Bar:=Bar+Q.FieldByName('UMSATZ').AsFloat
      else if ContainsText(UpperCase(Q.FieldByName('ZAHLART').AsString),'EC') or ContainsText(UpperCase(Q.FieldByName('ZAHLART').AsString),'KARTE') then EC:=EC+Q.FieldByName('UMSATZ').AsFloat;
      Q.Next;
    end;
  finally Q.Free; end;
end;

procedure ParseCash(const Raw:string; out Store,Stacker,Total:Double);
var L:TStringList; A,B:Int64;
begin
  Store:=0; Stacker:=0; Total:=0; L:=TStringList.Create;
  try
    L.Delimiter:='#'; L.StrictDelimiter:=True; L.DelimitedText:=Trim(Raw);
    A:=0; B:=0;
    if L.Count>2 then A:=StrToInt64Def(Trim(L[2]),0);
    if L.Count>3 then B:=StrToInt64Def(Trim(L[3]),0);
    Store:=A/100; Stacker:=B/100; Total:=(A+B)/100;
  finally L.Free; end;
end;

procedure RunZVTClose(out OK:Boolean; out Ergebnis:Integer; out Text,Data:string);
var Reg:TRegistry; SI:TShellExecuteInfo; Params,Exe,JsonFile,TriedPaths,RegData:string; StartTick:Cardinal; Aktiv,TestValue,KassenDruckValue:Integer;
begin
  OK:=False; Ergebnis:=1000; Text:=''; Data:='';
  Exe:=ResolveZVTExePath(TriedPaths);
  if not FileExists(Exe) then begin Text:='EasyZVT.exe nicht gefunden. Bitte im Admin unter ZVT den Pfad eintragen. Geprueft:'+sLineBreak+TriedPaths; Exit; end;
  ForceDirectories(ExtractFilePath(ParamStr(0))+'ZVT\');
  TestValue:=0;
  KassenDruckValue:=SCOConfig.ZVT_Kassedruck;
  if KassenDruckValue<=0 then KassenDruckValue:=1;
  Reg:=TRegistry.Create(KEY_WRITE);
  try
    Reg.RootKey:=HKEY_CURRENT_USER;
    if Reg.OpenKey('Software\GUB\ZVT',True) then begin
      Reg.WriteInteger('Aktiv',1); Reg.WriteInteger('Ergebnis',1000); Reg.WriteString('ErgebnisText','Kassenschnitt nicht abgeschlossen.');
      Reg.WriteString('Betrag','300');
      Reg.WriteString('COM','LAN'); Reg.WriteString('IP',SCOConfig.ZVT_Host); Reg.WriteString('Port',IntToStr(SCOConfig.ZVT_Port));
      Reg.WriteString('KasseNr',IntToStr(SCOConfig.ZVT_Kasse)); Reg.WriteString('Lizenz',SCOConfig.ZVT_Lizenz);
      Reg.WriteInteger('Funktion',2); Reg.WriteString('Ausgabepfad',ExtractFilePath(ParamStr(0))+'ZVT\');
      Reg.WriteInteger('Kassedruck',KassenDruckValue); Reg.WriteInteger('Test',TestValue);
    end;
  finally Reg.Free; end;
  Params:=Format('e KasseNr=%d COM=LAN IP=%s Port=%d Betrag=300 Lizenz=%s Kassedruck=%d Funktion=2 Ausgabepfad=%sZVT\',
    [SCOConfig.ZVT_Kasse,SCOConfig.ZVT_Host,SCOConfig.ZVT_Port,SCOConfig.ZVT_Lizenz,KassenDruckValue,ExtractFilePath(ParamStr(0))]);
  if TestValue<>0 then
    Params:=Params+' Test=1';
  FillChar(SI,SizeOf(SI),0); SI.cbSize:=SizeOf(SI); SI.fMask:=SEE_MASK_NOCLOSEPROCESS; SI.lpFile:=PChar(Exe); SI.lpParameters:=PChar(Params); SI.nShow:=SW_HIDE;
  LogPayment('ZVT KASSENSCHNITT EXE '+Exe);
  LogPayment('ZVT KASSENSCHNITT START '+Params);
  if not ShellExecuteEx(@SI) then begin Text:='EasyZVT Kassenschnitt konnte nicht gestartet werden.'; Exit; end;
  StartTick:=GetTickCount;
  repeat
    Sleep(500); Aktiv:=1;
    Reg:=TRegistry.Create(KEY_READ);
    try
      Reg.RootKey:=HKEY_CURRENT_USER;
      if Reg.OpenKey('Software\GUB\ZVT',False) then begin
        if Reg.ValueExists('Aktiv') then Aktiv:=Reg.ReadInteger('Aktiv');
        if Aktiv=0 then begin
          if Reg.ValueExists('Ergebnis') then Ergebnis:=Reg.ReadInteger('Ergebnis');
          if Reg.ValueExists('ErgebnisText') then Text:=Reg.ReadString('ErgebnisText');
          RegData:='';
          if Reg.ValueExists('ErgebnisLang') then RegData:=Reg.ReadString('ErgebnisLang');
          if Reg.ValueExists('Drucktext') then begin
            if RegData<>'' then RegData:=RegData+sLineBreak+sLineBreak;
            RegData:=RegData+Reg.ReadString('Drucktext');
          end;
          if RegData<>'' then Data:=RegData;
        end;
      end;
    finally Reg.Free; end;
    if GetTickCount-StartTick>180000 then begin
      Reg:=TRegistry.Create(KEY_READ);
      try
        Reg.RootKey:=HKEY_CURRENT_USER;
        if Reg.OpenKey('Software\GUB\ZVT',False) then begin
          if Reg.ValueExists('ErgebnisText') then Text:=Reg.ReadString('ErgebnisText');
          RegData:='';
          if Reg.ValueExists('ErgebnisLang') then RegData:=Reg.ReadString('ErgebnisLang');
          if Reg.ValueExists('Drucktext') then begin
            if RegData<>'' then RegData:=RegData+sLineBreak+sLineBreak;
            RegData:=RegData+Reg.ReadString('Drucktext');
          end;
          if RegData<>'' then Data:=RegData;
        end;
      finally Reg.Free; end;
      if Text='' then Text:='Zeitueberschreitung beim ZVT-Kassenschnitt.'
      else Text:='Zeitueberschreitung beim ZVT-Kassenschnitt. Letzter ZVT-Status: '+Text;
      LogPayment('ZVT KASSENSCHNITT TIMEOUT '+Text);
      Exit;
    end;
  until Aktiv=0;
  OK:=Ergebnis=0;
  JsonFile:=ExtractFilePath(ParamStr(0))+'ZVT\ZVT_Ergebnis_'+IntToStr(SCOConfig.ZVT_Kasse)+'.json';
  if (Data='') and FileExists(JsonFile) then try Data:=TFile.ReadAllText(JsonFile,TEncoding.UTF8); except end;
  LogPayment('ZVT KASSENSCHNITT END Ergebnis='+IntToStr(Ergebnis)+' Text='+Text);
end;

function DailyCloseRunJson(ACloseDate:TDateTime; Automatic:Boolean):string;
var Q:TFDQuery; ID,Bons,Positions,ZResult:Integer; Total,B7,N7,T7,B19,N19,T19,Bar,EC,CashTotal,CashStore,CashStacker:Double;
  ZOK,COK:Boolean; ZText,ZData,CText,Errors,Status:string; Cash:TCashLogyService; CR:TCashLogyResult;
begin
  CloseLock.Enter;
  try
    try
      SCOConfig.Load;
      LogTransaction('KASSENABSCHLUSS RUN START Datum=' + FormatDateTime('yyyy-mm-dd', ACloseDate) + ' Auto=' + BoolToStr(Automatic, True));
      EnsureTable;
    if DailyCloseExists(ACloseDate) then
    begin
      LogTransaction('KASSENABSCHLUSS SKIP EXISTS Datum=' + FormatDateTime('yyyy-mm-dd', ACloseDate));
      Exit('{"ok":false,"message":"Fuer diesen Tag und diese Kasse existiert bereits ein Abschluss."}');
    end;
    ReadTotals(ACloseDate,Bons,Positions,Total,B7,N7,T7,B19,N19,T19,Bar,EC);
    ZOK:=not (SCOConfig.DailyCloseZVT and SCOConfig.PaymentEC); ZResult:=0; ZText:='Nicht aktiviert'; ZData:='';
    COK:=not (SCOConfig.DailyCloseCashLogy and SCOConfig.PaymentBar); CText:='Nicht aktiviert'; CashTotal:=0; CashStore:=0; CashStacker:=0; Errors:='';
    if SCOConfig.DailyCloseCashLogy and SCOConfig.PaymentBar then begin
      Cash:=TCashLogyService.Create(SCOConfig.CashLogyConnectorHost,SCOConfig.CashLogyConnectorPort);
      try CR:=Cash.MoneyStatus; COK:=CR.OK; CText:=CR.RawResponse; ParseCash(CR.RawResponse,CashStore,CashStacker,CashTotal); if not COK then Errors:=Errors+'CashLogy: '+CR.StatusText+sLineBreak; finally Cash.Free; end;
    end;
    if SCOConfig.DailyCloseZVT and SCOConfig.PaymentEC then begin RunZVTClose(ZOK,ZResult,ZText,ZData); if not ZOK then Errors:=Errors+'ZVT: '+ZText+sLineBreak; end;
    if ZOK and COK then Status:='OK' else Status:='TEILFEHLER';
    Q:=TFDQuery.Create(nil);
    try
      Q.Connection:=FB; Q.SQL.Text:='select coalesce(max(ID),0)+1 ID from SCO_KASSENABSCHLUSS'; Q.Open; ID:=Q.FieldByName('ID').AsInteger; Q.Close;
      Q.SQL.Text:='insert into SCO_KASSENABSCHLUSS (ID,FILIAL_ID,GERAET,ABSCHLUSSDATUM,ABSCHLUSSZEIT,STATUS,AUTOMATISCH,BONS,POSITIONEN,'+
        'UMSATZ_GESAMT,BRUTTO_7,NETTO_7,MWST_7,BRUTTO_19,NETTO_19,MWST_19,UMSATZ_BAR,UMSATZ_EC,ZVT_AKTIV,ZVT_OK,ZVT_ERGEBNIS,ZVT_TEXT,ZVT_DATEN,'+
        'CASHLOGY_AKTIV,CASHLOGY_OK,CASHLOGY_BESTAND,CASHLOGY_STORE,CASHLOGY_STACKER,CASHLOGY_TEXT,FEHLER,ERSTELLT) values ('+
        ':ID,:F,:G,:D,current_timestamp,:S,:A,:BONS,:POS,:TOTAL,:B7,:N7,:T7,:B19,:N19,:T19,:BAR,:EC,:ZA,:ZO,:ZR,:ZT,:ZD,:CA,:CO,:CB,:CS,:CK,:CT,:FE,current_timestamp)';
      Q.ParamByName('ID').AsInteger:=ID; Q.ParamByName('F').AsInteger:=StrToIntDef(SCOConfig.BonjournalFilialId,SCOConfig.KundenNr); Q.ParamByName('G').AsInteger:=SCOConfig.ZVT_Kasse;
      Q.ParamByName('D').AsDate:=ACloseDate; Q.ParamByName('S').AsString:=Status; Q.ParamByName('A').AsInteger:=Ord(Automatic); Q.ParamByName('BONS').AsInteger:=Bons; Q.ParamByName('POS').AsInteger:=Positions;
      Q.ParamByName('TOTAL').AsFloat:=Total; Q.ParamByName('B7').AsFloat:=B7; Q.ParamByName('N7').AsFloat:=N7; Q.ParamByName('T7').AsFloat:=T7; Q.ParamByName('B19').AsFloat:=B19; Q.ParamByName('N19').AsFloat:=N19; Q.ParamByName('T19').AsFloat:=T19;
      Q.ParamByName('BAR').AsFloat:=Bar; Q.ParamByName('EC').AsFloat:=EC; Q.ParamByName('ZA').AsInteger:=Ord(SCOConfig.DailyCloseZVT and SCOConfig.PaymentEC); Q.ParamByName('ZO').AsInteger:=Ord(ZOK); Q.ParamByName('ZR').AsInteger:=ZResult;
      Q.ParamByName('ZT').AsString:=ZText; Q.ParamByName('ZD').AsString:=ZData; Q.ParamByName('CA').AsInteger:=Ord(SCOConfig.DailyCloseCashLogy and SCOConfig.PaymentBar); Q.ParamByName('CO').AsInteger:=Ord(COK);
      Q.ParamByName('CB').AsFloat:=CashTotal; Q.ParamByName('CS').AsFloat:=CashStore; Q.ParamByName('CK').AsFloat:=CashStacker; Q.ParamByName('CT').AsString:=CText; Q.ParamByName('FE').AsString:=Errors; Q.ExecSQL;
    finally Q.Free; end;
    LogTransaction('KASSENABSCHLUSS '+Status+' Datum='+FormatDateTime('yyyy-mm-dd',ACloseDate)+' Umsatz='+FormatFloat('0.00',Total));
    Result:='{"ok":'+LowerCase(BoolToStr(Status='OK',True))+',"status":"'+Status+'","message":"Kassenabschluss '+J(Status)+' gespeichert.","id":'+IntToStr(ID)+'}';
    except
      on E:Exception do begin
        LogError('KASSENABSCHLUSS ERROR '+E.ClassName+': '+E.Message);
        Result:='{"ok":false,"message":"'+J(E.Message)+'"}';
      end;
    end;
  finally
    CloseLock.Leave;
  end;
end;

function CloseLine(const C: Char): string;
begin
  Result:=StringOfChar(C, 42);
end;

function CloseMoney(V: Double): string;
begin
  Result:=FormatFloat('0.00', V)+' EUR';
end;

function CloseTwoCol(const A,B: string): string;
var W:Integer; L,R:string;
begin
  W:=42;
  L:=A; R:=B;
  if Length(L)>W-12 then L:=Copy(L,1,W-12);
  if W-Length(L)-Length(R)>1 then
    Result:=L+StringOfChar(' ', W-Length(L)-Length(R))+R
  else
    Result:=L+' '+R;
end;

function BuildDailyCloseReceiptText(ID: Integer): string;
var Q:TFDQuery; L:TStringList; ZData,CashText,Err:string;
begin
  Result:='';
  EnsureTable;
  Q:=TFDQuery.Create(nil);
  L:=TStringList.Create;
  try
    Q.Connection:=FB;
    Q.SQL.Text:='select * from SCO_KASSENABSCHLUSS where ID=:ID';
    Q.ParamByName('ID').AsInteger:=ID;
    Q.Open;
    if Q.IsEmpty then
      raise Exception.Create('Kassenabschluss nicht gefunden.');

    L.Add('          KASSENABSCHLUSS');
    L.Add(CloseLine('='));
    L.Add('Tag: '+FormatDateTime('dd.mm.yyyy', Q.FieldByName('ABSCHLUSSDATUM').AsDateTime));
    L.Add('Erstellt: '+FormatDateTime('dd.mm.yyyy hh:nn:ss', Q.FieldByName('ABSCHLUSSZEIT').AsDateTime));
    L.Add('Status: '+Q.FieldByName('STATUS').AsString);
    L.Add(CloseLine('-'));
    L.Add(CloseTwoCol('Bons', Q.FieldByName('BONS').AsString));
    L.Add(CloseTwoCol('Positionen', Q.FieldByName('POSITIONEN').AsString));
    L.Add(CloseTwoCol('Umsatz gesamt', CloseMoney(Q.FieldByName('UMSATZ_GESAMT').AsFloat)));
    L.Add(CloseLine('-'));
    L.Add('Umsatzsteuer 7%');
    L.Add(CloseTwoCol('Brutto', CloseMoney(Q.FieldByName('BRUTTO_7').AsFloat)));
    L.Add(CloseTwoCol('Netto', CloseMoney(Q.FieldByName('NETTO_7').AsFloat)));
    L.Add(CloseTwoCol('MwSt', CloseMoney(Q.FieldByName('MWST_7').AsFloat)));
    L.Add('Umsatzsteuer 19%');
    L.Add(CloseTwoCol('Brutto', CloseMoney(Q.FieldByName('BRUTTO_19').AsFloat)));
    L.Add(CloseTwoCol('Netto', CloseMoney(Q.FieldByName('NETTO_19').AsFloat)));
    L.Add(CloseTwoCol('MwSt', CloseMoney(Q.FieldByName('MWST_19').AsFloat)));
    L.Add(CloseLine('-'));
    L.Add(CloseTwoCol('Bar', CloseMoney(Q.FieldByName('UMSATZ_BAR').AsFloat)));
    L.Add(CloseTwoCol('EC/Karte', CloseMoney(Q.FieldByName('UMSATZ_EC').AsFloat)));

    ZData:=Trim(Q.FieldByName('ZVT_DATEN').AsString);
    if ZData<>'' then begin
      L.Add(CloseLine('='));
      L.Add('ZVT / Kartenterminal');
      L.Add(Q.FieldByName('ZVT_TEXT').AsString);
      L.Add(CloseLine('-'));
      L.Add(ZData);
    end;

    CashText:=Trim(Q.FieldByName('CASHLOGY_TEXT').AsString);
    if CashText<>'' then begin
      L.Add(CloseLine('='));
      L.Add('CashLogy / Geldbestand');
      L.Add(CashText);
    end;

    Err:=Trim(Q.FieldByName('FEHLER').AsString);
    if Err<>'' then begin
      L.Add(CloseLine('='));
      L.Add('Fehler / Hinweise');
      L.Add(Err);
    end;
    L.Add(CloseLine('='));
    L.Add(''); L.Add('');
    Result:=L.Text;
  finally
    L.Free;
    Q.Free;
  end;
end;

function DailyCloseReceiptJson(ID: Integer): string;
var T:string;
begin
  try
    T:=BuildDailyCloseReceiptText(ID);
    Result:='{"ok":true,"message":"Kassenabschluss-Bon erstellt.","text":"'+J(T)+'"}';
  except
    on E:Exception do begin
      LogError('KASSENABSCHLUSS RECEIPT ERROR '+E.ClassName+': '+E.Message);
      Result:='{"ok":false,"message":"'+J(E.Message)+'","text":""}';
    end;
  end;
end;

function DailyClosePrintJson(ID: Integer): string;
var T:string; R:TSCOReceiptService;
begin
  try
    T:=BuildDailyCloseReceiptText(ID);
    R:=TSCOReceiptService.Create;
    try
      Result:=R.PrintPlainText(T);
    finally
      R.Free;
    end;
  except
    on E:Exception do begin
      LogError('KASSENABSCHLUSS PRINT ERROR '+E.ClassName+': '+E.Message);
      Result:='{"ok":false,"message":"'+J(E.Message)+'"}';
    end;
  end;
end;
function DailyCloseListJson:string;
var Q:TFDQuery; First:Boolean;
begin
  EnsureTable; Q:=TFDQuery.Create(nil);
  try
    Q.Connection:=FB; Q.SQL.Text:='select first 100 * from SCO_KASSENABSCHLUSS order by ABSCHLUSSDATUM desc,ID desc'; Q.Open; Result:='{"ok":true,"items":['; First:=True;
    while not Q.Eof do begin
      if not First then Result:=Result+',';
      Result:=Result+'{"id":'+Q.FieldByName('ID').AsString+',"date":"'+FormatDateTime('yyyy-mm-dd',Q.FieldByName('ABSCHLUSSDATUM').AsDateTime)+'","time":"'+FormatDateTime('dd.mm.yyyy hh:nn:ss',Q.FieldByName('ABSCHLUSSZEIT').AsDateTime)+'",'+
        '"status":"'+J(Q.FieldByName('STATUS').AsString)+'","automatic":'+LowerCase(BoolToStr(Q.FieldByName('AUTOMATISCH').AsInteger=1,True))+',"receipts":'+Q.FieldByName('BONS').AsString+',"positions":'+Q.FieldByName('POSITIONEN').AsString+
        ',"total":'+N(Q.FieldByName('UMSATZ_GESAMT').AsFloat)+',"gross7":'+N(Q.FieldByName('BRUTTO_7').AsFloat)+',"tax7":'+N(Q.FieldByName('MWST_7').AsFloat)+',"gross19":'+N(Q.FieldByName('BRUTTO_19').AsFloat)+',"tax19":'+N(Q.FieldByName('MWST_19').AsFloat)+
        ',"cash":'+N(Q.FieldByName('UMSATZ_BAR').AsFloat)+',"ec":'+N(Q.FieldByName('UMSATZ_EC').AsFloat)+',"zvtOk":'+LowerCase(BoolToStr(Q.FieldByName('ZVT_OK').AsInteger=1,True))+',"zvtResult":'+Q.FieldByName('ZVT_ERGEBNIS').AsString+',"zvtText":"'+J(Q.FieldByName('ZVT_TEXT').AsString)+'"'+
        ',"cashlogyOk":'+LowerCase(BoolToStr(Q.FieldByName('CASHLOGY_OK').AsInteger=1,True))+',"cashlogyBalance":'+N(Q.FieldByName('CASHLOGY_BESTAND').AsFloat)+',"zvtData":"'+J(Q.FieldByName('ZVT_DATEN').AsString)+'","cashlogyText":"'+J(Q.FieldByName('CASHLOGY_TEXT').AsString)+'","error":"'+J(Q.FieldByName('FEHLER').AsString)+'"}';
      First:=False; Q.Next;
    end; Result:=Result+']}';
  except on E:Exception do Result:='{"ok":false,"message":"'+J(E.Message)+'","items":[]}'; end;
  Q.Free;
end;

procedure CheckScheduledDailyClose;
var H,M:Integer; P:TArray<string>; Target:TDateTime; Res:string;
begin
  try
    SCOConfig.Load;
    if not SCOConfig.DailyCloseActive then Exit;
    P:=SCOConfig.DailyCloseTime.Split([':']);
    if Length(P)<2 then
    begin
      LogError('KASSENABSCHLUSS AUTO ungueltige Uhrzeit: ' + SCOConfig.DailyCloseTime);
      Exit;
    end;
    H:=StrToIntDef(P[0],2); M:=StrToIntDef(P[1],0);
    if Time<EncodeTime(H,M,0,0) then Exit;
    Target:=Date-1;
    if DailyCloseExists(Target) then
    begin
      LogTransaction('KASSENABSCHLUSS AUTO SKIP EXISTS Datum=' + FormatDateTime('yyyy-mm-dd', Target));
      Exit;
    end;
    LogTransaction('KASSENABSCHLUSS AUTO START Datum=' + FormatDateTime('yyyy-mm-dd', Target));
    Res:=DailyCloseRunJson(Target,True);
    LogTransaction('KASSENABSCHLUSS AUTO RESULT ' + Res);
  except
    on E:Exception do
      LogError('KASSENABSCHLUSS AUTO ERROR ' + E.ClassName + ': ' + E.Message);
  end;
end;

initialization CloseLock:=TCriticalSection.Create;
finalization CloseLock.Free;
end.








