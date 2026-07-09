unit SCO_LabelDesignerService;

interface

function LabelTemplateListJson: string;
function LabelTemplateGetJson(const ID: string): string;
function LabelTemplateSaveJson(const Body: string): string;
function LabelTemplateDeleteJson(const ID: string): string;
function LabelTemplateZplByNumber(Number: Integer; out TemplateName: string): string;

implementation

uses
  System.SysUtils, System.Classes, System.Types, System.IOUtils, System.JSON,
  SCO_Logger;

function TemplatePath: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'LabelTemplates');
  ForceDirectories(Result);
end;

function SafeID(const Value: string): string;
var C: Char;
begin
  Result := '';
  for C in LowerCase(Trim(Value)) do
    if CharInSet(C, ['a'..'z', '0'..'9', '-', '_']) then Result := Result + C;
end;

function EscapeJson(const S: string): string;
begin
  Result := S;
  Result := StringReplace(Result, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
end;

function JsonString(O: TJSONObject; const Name, Default: string): string;
var V: TJSONValue;
begin
  Result := Default;
  if O = nil then Exit;
  V := O.GetValue(Name);
  if V <> nil then Result := V.Value;
end;

function JsonInt(O: TJSONObject; const Name: string; Default: Integer): Integer;
begin
  Result := StrToIntDef(JsonString(O, Name, IntToStr(Default)), Default);
end;

function JsonNumber(O: TJSONObject; const Name, Default: string): string;
begin
  Result := StringReplace(JsonString(O, Name, Default), ',', '.', [rfReplaceAll]);
  if Trim(Result) = '' then Result := Default;
end;

function ReadTemplate(const FileName: string; out O: TJSONObject): TJSONValue;
var Raw: string;
begin
  O := nil;
  Result := nil;
  if not TFile.Exists(FileName) then Exit;
  Raw := TFile.ReadAllText(FileName, TEncoding.UTF8);
  Result := TJSONObject.ParseJSONValue(Raw);
  if Result is TJSONObject then O := TJSONObject(Result);
end;

function NextTemplateNumber: Integer;
var Files: TStringDynArray; F: string; V: TJSONValue; O: TJSONObject; N: Integer;
begin
  Result := 1;
  Files := TDirectory.GetFiles(TemplatePath, '*.json');
  for F in Files do
  begin
    V := nil;
    try
      V := ReadTemplate(F, O);
      N := JsonInt(O, 'number', 0);
      if N >= Result then Result := N + 1;
    except
    end;
    V.Free;
  end;
end;

function LabelTemplateListJson: string;
var Files: TStringDynArray; FileName, Item: string; V: TJSONValue; O: TJSONObject; Pair: TJSONPair; First: Boolean; N: Integer;
begin
  Result := '[';
  First := True;
  Files := TDirectory.GetFiles(TemplatePath, '*.json');
  for FileName in Files do
  begin
    V := nil;
    try
      V := ReadTemplate(FileName, O);
      if O = nil then Continue;
      N := JsonInt(O, 'number', 0);
      if N <= 0 then
      begin
        N := NextTemplateNumber;
        Pair := O.RemovePair('number');
        Pair.Free;
        O.AddPair('number', TJSONNumber.Create(N));
        TFile.WriteAllText(FileName, O.ToJSON, TEncoding.UTF8);
      end;
      Item := '{' +
        '"id":"' + EscapeJson(JsonString(O, 'id', TPath.GetFileNameWithoutExtension(FileName))) + '",' +
        '"number":' + IntToStr(N) + ',' +
        '"name":"' + EscapeJson(JsonString(O, 'name', 'Etikett')) + '",' +
        '"labelType":"' + EscapeJson(JsonString(O, 'labelType', 'standard')) + '",' +
        '"widthMm":' + JsonNumber(O, 'widthMm', '44') + ',' +
        '"heightMm":' + JsonNumber(O, 'heightMm', '19') + ',' +
        '"dpi":' + JsonNumber(O, 'dpi', '300') + '}';
      if not First then Result := Result + ',';
      Result := Result + Item;
      First := False;
    except
      on E: Exception do LogError('LABEL TEMPLATE LIST ' + FileName + ': ' + E.Message);
    end;
    V.Free;
  end;
  Result := Result + ']';
end;

function LabelTemplateGetJson(const ID: string): string;
var FileName, Key: string;
begin
  Key := SafeID(ID);
  FileName := TPath.Combine(TemplatePath, Key + '.json');
  if (Key = '') or not TFile.Exists(FileName) then
    Exit('{"ok":false,"message":"Etikettenvorlage nicht gefunden."}');
  Result := TFile.ReadAllText(FileName, TEncoding.UTF8);
end;

function TemplateNumberUsed(Number: Integer; const ExceptID: string): Boolean;
var
  Files: TStringDynArray;
  F, CurrentID: string;
  V: TJSONValue;
  O: TJSONObject;
begin
  Result := False;
  if Number <= 0 then Exit;
  Files := TDirectory.GetFiles(TemplatePath, '*.json');
  for F in Files do
  begin
    V := nil;
    try
      V := ReadTemplate(F, O);
      if O = nil then Continue;
      CurrentID := SafeID(JsonString(O, 'id', TPath.GetFileNameWithoutExtension(F)));
      if (JsonInt(O, 'number', 0) = Number) and
         not SameText(CurrentID, SafeID(ExceptID)) then
        Exit(True);
    finally
      V.Free;
    end;
  end;
end;
function LabelTemplateSaveJson(const Body: string): string;
var V: TJSONValue; O: TJSONObject; Pair: TJSONPair; ID, FileName: string; N: Integer;
begin
  V := TJSONObject.ParseJSONValue(Body);
  try
    if not (V is TJSONObject) then Exit('{"ok":false,"message":"Vorlagendaten sind ungueltig."}');
    O := TJSONObject(V);
    ID := SafeID(JsonString(O, 'id', ''));
    if ID = '' then
    begin
      ID := 'label-' + FormatDateTime('yyyymmdd-hhnnsszzz', Now);
      O.AddPair('id', ID);
    end;
    N := JsonInt(O, 'number', 0);
    if (N > 0) and TemplateNumberUsed(N, ID) then
      Exit('{"ok":false,"message":"Vorlagennummer ' + IntToStr(N) + ' ist bereits vergeben."}');
    if N <= 0 then
    begin
      N := NextTemplateNumber;
      Pair := O.RemovePair('number');
      Pair.Free;
      O.AddPair('number', TJSONNumber.Create(N));
    end;
    FileName := TPath.Combine(TemplatePath, ID + '.json');
    TFile.WriteAllText(FileName, O.ToJSON, TEncoding.UTF8);
    LogTransaction('LABEL TEMPLATE SAVE id=' + ID + ' number=' + IntToStr(N));
    Result := '{"ok":true,"id":"' + EscapeJson(ID) + '","number":' + IntToStr(N) + ',"message":"Etikettenvorlage gespeichert."}';
  except
    on E: Exception do
    begin
      LogError('LABEL TEMPLATE SAVE ERROR: ' + E.Message);
      Result := '{"ok":false,"message":"' + EscapeJson(E.Message) + '"}';
    end;
  end;
  V.Free;
end;

function LabelTemplateDeleteJson(const ID: string): string;
var FileName, Key: string;
begin
  Key := SafeID(ID);
  FileName := TPath.Combine(TemplatePath, Key + '.json');
  try
    if (Key <> '') and TFile.Exists(FileName) then TFile.Delete(FileName);
    LogTransaction('LABEL TEMPLATE DELETE id=' + Key);
    Result := '{"ok":true,"message":"Etikettenvorlage geloescht."}';
  except
    on E: Exception do Result := '{"ok":false,"message":"' + EscapeJson(E.Message) + '"}';
  end;
end;

function LabelTemplateZplByNumber(Number: Integer; out TemplateName: string): string;
var Files: TStringDynArray; F: string; V: TJSONValue; O: TJSONObject;
begin
  Result := '';
  TemplateName := '';
  if Number <= 0 then Exit;
  Files := TDirectory.GetFiles(TemplatePath, '*.json');
  for F in Files do
  begin
    V := nil;
    try
      V := ReadTemplate(F, O);
      if (O <> nil) and (JsonInt(O, 'number', 0) = Number) then
      begin
        TemplateName := JsonString(O, 'name', 'Etikett ' + IntToStr(Number));
        Result := JsonString(O, 'generatedZpl', '');
        Exit;
      end;
    finally
      V.Free;
    end;
  end;
end;

end.
