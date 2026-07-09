unit SCO_Logger;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.IOUtils;

procedure LogInfo(const Msg: string);
procedure LogError(const Msg: string);
procedure LogRequest(const Method, Path, IP: string);
procedure LogTransaction(const Msg: string);
procedure LogPayment(const Msg: string);
procedure LogWeighing(const Msg: string);
procedure LogEichamtWeighing(const Source: string; PLU: Integer; const Article: string; Gross, Tara, Net: Double; const AlibiNo, Raw, Note: string);

implementation

var
  LogLock: TCriticalSection;

function LogDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'logs\';
  if not DirectoryExists(Result) then
    ForceDirectories(Result);
end;

function LogFileName: string;
begin
  Result := LogDir + 'sco_' + FormatDateTime('yyyy-mm-dd', Date) + '.log';
end;

function WeighingLogFileName: string;
begin
  Result := LogDir + 'verwiegung_' + FormatDateTime('yyyy-mm-dd', Date) + '.log';
end;

function EichamtLogFileName: string;
begin
  Result := LogDir + 'eichamt_verwiegung_' + FormatDateTime('yyyy-mm-dd', Date) + '.csv';
end;

function CsvField(const S: string): string;
begin
  Result := StringReplace(S, '"', '""', [rfReplaceAll]);
  if (Pos(';', Result) > 0) or (Pos('"', Result) > 0) or (Pos(#13, Result) > 0) or (Pos(#10, Result) > 0) then
    Result := '"' + Result + '"';
end;

function CsvFloat(Value: Double): string;
begin
  Result := FormatFloat('0.000', Value);
end;

procedure WriteDirectLog(const FileName, Level, Msg: string);
var
  Line: string;
begin
  if not Assigned(LogLock) then
    Exit;
  LogLock.Enter;
  try
    Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' [' + Level + '] ' + Msg + sLineBreak;
    TFile.AppendAllText(FileName, Line, TEncoding.UTF8);
  finally
    LogLock.Leave;
  end;
end;

procedure WriteLog(const Level, Msg: string);
var
  SL: TStringList;
  Line: string;
begin
  if not Assigned(LogLock) then
    Exit;

  LogLock.Enter;
  try
    Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' [' + Level + '] ' + Msg;
    SL := TStringList.Create;
    try
      if FileExists(LogFileName) then
        SL.LoadFromFile(LogFileName, TEncoding.UTF8);
      SL.Add(Line);
      SL.SaveToFile(LogFileName, TEncoding.UTF8);
    finally
      SL.Free;
    end;
  finally
    LogLock.Leave;
  end;
end;

procedure LogInfo(const Msg: string);
begin
  WriteLog('INFO', Msg);
end;

procedure LogPayment(const Msg: string);
begin
  WriteLog('PAYMENT', Msg);
end;

procedure LogWeighing(const Msg: string);
begin
  WriteDirectLog(WeighingLogFileName, 'WEIGHING', Msg);
end;

procedure LogEichamtWeighing(const Source: string; PLU: Integer; const Article: string; Gross, Tara, Net: Double; const AlibiNo, Raw, Note: string);
var
  FileName, Line: string;
  HasFile: Boolean;
begin
  if not Assigned(LogLock) then
    Exit;
  FileName := EichamtLogFileName;
  LogLock.Enter;
  try
    HasFile := FileExists(FileName);
    if not HasFile then
      TFile.AppendAllText(FileName, 'Zeit;Quelle;PLU;Artikel;Brutto_kg;Tara_kg;Netto_kg;AlibiNr;Rohdaten;Hinweis' + sLineBreak, TEncoding.UTF8);
    Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ';' +
      CsvField(Source) + ';' +
      IntToStr(PLU) + ';' +
      CsvField(Article) + ';' +
      CsvFloat(Gross) + ';' +
      CsvFloat(Tara) + ';' +
      CsvFloat(Net) + ';' +
      CsvField(AlibiNo) + ';' +
      CsvField(Raw) + ';' +
      CsvField(Note) + sLineBreak;
    TFile.AppendAllText(FileName, Line, TEncoding.UTF8);
  finally
    LogLock.Leave;
  end;
end;

procedure LogError(const Msg: string);
begin
  WriteLog('ERROR', Msg);
end;

procedure LogRequest(const Method, Path, IP: string);
begin
  WriteLog('REQUEST', Method + ' ' + Path + ' IP=' + IP);
end;

procedure LogTransaction(const Msg: string);
begin
  WriteLog('TRANSACTION', Msg);
end;

initialization
  LogLock := TCriticalSection.Create;

finalization
  FreeAndNil(LogLock);

end.