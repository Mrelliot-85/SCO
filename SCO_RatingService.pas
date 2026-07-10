unit SCO_RatingService;

interface

function RatingSaveJson(const JsonText: string): string;

implementation

uses
  System.SysUtils,
  System.JSON,
  FireDAC.Comp.Client,
  SCO_Config,
  SCO_DB,
  SCO_Logger;

function BoolJson(Value: Boolean): string;
begin
  if Value then
    Result := 'true'
  else
    Result := 'false';
end;

function JsonNumber(Value: Double): string;
begin
  Result := StringReplace(FormatFloat('0.00', Value), ',', '.', [rfReplaceAll]);
end;

function ObjInt(Obj: TJSONObject; const Name: string; Default: Integer): Integer;
var
  V: TJSONValue;
begin
  Result := Default;
  if Obj = nil then
    Exit;
  V := Obj.GetValue(Name);
  if V <> nil then
    Result := StrToIntDef(V.Value, Default);
end;

function ObjRating(Obj: TJSONObject; Index: Integer; Default: Double): Double;
var
  Arr: TJSONArray;
  V: TJSONValue;
begin
  Result := Default;
  if Obj = nil then
    Exit;
  V := Obj.GetValue('ratings');
  if not (V is TJSONArray) then
    Exit;
  Arr := TJSONArray(V);
  if (Index < 0) or (Index >= Arr.Count) then
    Exit;
  Result := StrToFloatDef(StringReplace(Arr.Items[Index].Value, '.', ',', [rfReplaceAll]), Default);
  if Result < 0 then
    Result := 0;
  if Result > 5 then
    Result := 5;
end;

function NextBewertungId: Integer;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text := 'select coalesce(max(ID), -1) + 1 as NEXT_ID from BEWERTUNG';
    Q.Open;
    Result := Q.FieldByName('NEXT_ID').AsInteger;
  finally
    Q.Free;
  end;
end;

function RatingSaveJson(const JsonText: string): string;
var
  RootValue: TJSONValue;
  Obj: TJSONObject;
  Q: TFDQuery;
  BonNo, FilialId, NewId: Integer;
  R1, R2, R3, R4, Avg: Double;
begin
  Result := '{"ok":false,"message":"Bewertung konnte nicht gespeichert werden."}';
  RootValue := nil;
  try
    RootValue := TJSONObject.ParseJSONValue(JsonText);
    if not (RootValue is TJSONObject) then
      Exit('{"ok":false,"message":"Ungueltige Bewertungsdaten."}');
    Obj := TJSONObject(RootValue);

    BonNo := ObjInt(Obj, 'bonNo', ObjInt(Obj, 'bon', 0));
    if BonNo <= 0 then
      Exit('{"ok":false,"message":"Bewertung ohne Bonnummer wird nicht gespeichert."}');

    R1 := ObjRating(Obj, 0, 5);
    R2 := ObjRating(Obj, 1, 5);
    R3 := ObjRating(Obj, 2, 5);
    R4 := ObjRating(Obj, 3, 5);
    Avg := (R1 + R2 + R3 + R4) / 4;

    SCOConfig.Load;
    FilialId := StrToIntDef(Trim(SCOConfig.BonjournalFilialId), 0);
    if FilialId = 0 then
      FilialId := SCOConfig.KundenNr;

    NewId := NextBewertungId;

    Q := TFDQuery.Create(nil);
    try
      Q.Connection := FB;
      Q.SQL.Text :=
        'insert into BEWERTUNG ' +
        '(ID, BON, DATUM, RATING1, RATING2, RATING3, RATING4, FILIAL_ID, RATING) ' +
        'values (:ID, :BON, :DATUM, :R1, :R2, :R3, :R4, :FILIAL_ID, :RATING)';
      Q.ParamByName('ID').AsInteger := NewId;
      Q.ParamByName('BON').AsInteger := BonNo;
      Q.ParamByName('DATUM').AsDateTime := Date;
      Q.ParamByName('R1').AsFloat := R1;
      Q.ParamByName('R2').AsFloat := R2;
      Q.ParamByName('R3').AsFloat := R3;
      Q.ParamByName('R4').AsFloat := R4;
      Q.ParamByName('FILIAL_ID').AsInteger := FilialId;
      Q.ParamByName('RATING').AsFloat := Avg;
      Q.ExecSQL;
    finally
      Q.Free;
    end;

    LogTransaction('RATING SAVE bon=' + IntToStr(BonNo) + ' rating=' + FormatFloat('0.00', Avg));
    Result := '{"ok":true,"message":"Bewertung gespeichert.","id":' + IntToStr(NewId) +
      ',"bon":' + IntToStr(BonNo) + ',"rating":' + JsonNumber(Avg) +
      ',"filialId":' + IntToStr(FilialId) + '}';
  except
    on E: Exception do
    begin
      LogError('RATING SAVE ERROR ' + E.ClassName + ': ' + E.Message);
      Result := '{"ok":false,"message":"' + JsonEscape(E.Message) + '"}';
    end;
  end;
  RootValue.Free;
end;

end.

