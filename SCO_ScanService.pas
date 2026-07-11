unit SCO_ScanService;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Classes,
  FireDAC.Comp.Client;

type
  TSCOScanService = class
  private
    FConn: TFDConnection;

    function JsonEscape(const S: string): string;
    function GetArtikelByEAN(const EAN: string): string;
    function GetArtikelByPLU(const PLU: string): string;

  public
    constructor Create(AConn: TFDConnection);

    function ScanEAN(const EAN: string): string;
  end;

implementation

uses SCO_CONFIG;

function VatRateFromFields(Q: TFDQuery): Integer;
var
  S: string;
  N: Integer;
begin
  Result := 7;
  if Q.FindField('MWSTSATZ1') <> nil then
  begin
    S := Q.FieldByName('MWSTSATZ1').AsString;
    S := StringReplace(S, '%', '', [rfReplaceAll]);
    S := StringReplace(S, ',', '.', [rfReplaceAll]);
    N := Round(StrToFloatDef(S, 0));
    if (N = 7) or (N = 19) then
      Exit(N);
  end;

  if Q.FindField('MWST_1') <> nil then
  begin
    N := Q.FieldByName('MWST_1').AsInteger;
    if N = 1 then
      Exit(19);
    if N = 2 then
      Exit(7);
  end;
end;

constructor TSCOScanService.Create(AConn: TFDConnection);
begin
  inherited Create;
  FConn := AConn;
end;

function TSCOScanService.JsonEscape(const S: string): string;
begin
  Result := StringReplace(S, '"', '\"', [rfReplaceAll]);
end;

function TSCOScanService.GetArtikelByEAN(const EAN: string): string;
var
  Q: TFDQuery;
  GP: Double;
  VatRate: Integer;
begin
  Result := '{"ok":false,"message":"Artikel nicht gefunden"}';

  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConn;

    Q.SQL.Text :=
      'SELECT ' +
      '  ID, NUMMER, BEZEICHNUNG, ME_BEZ, VK_BRUTTO, WG, MWST_1, MWSTSATZ1 ' +
      'FROM VARTIKEL ' +
      'WHERE trim(cast(EAN as varchar(30))) = :EAN';

    Q.ParamByName('EAN').AsString := EAN;
    Q.Open;

    if not Q.IsEmpty then
    begin
      GP := Q.FieldByName('VK_BRUTTO').AsFloat;
      VatRate := VatRateFromFields(Q);

      Result :=
        '{' +
        '"ok":true,' +
        '"type":"ean",' +
        '"plu":"' + Q.FieldByName('NUMMER').AsString + '",' +
        '"name":"' + JsonEscape(Q.FieldByName('BEZEICHNUNG').AsString) + '",' +
        '"unit":"' + JsonEscape(Q.FieldByName('ME_BEZ').AsString) + '",' +
        '"ep":' + StringReplace(FloatToStr(GP), ',', '.', []) + ',' +
        '"qty":1,' +
        '"gp":' + StringReplace(FloatToStr(GP), ',', '.', []) + ',' +
        '"vatRate":' + IntToStr(VatRate) + ',' +
        '"mwst":' + IntToStr(VatRate) + ',' +
        '"wg":' + Q.FieldByName('WG').AsString +
        '}';
    end;

  finally
    Q.Free;
  end;
end;

function TSCOScanService.GetArtikelByPLU(const PLU: string): string;
var
  Q: TFDQuery;
  VatRate: Integer;
begin
  Result := '{"ok":false}';

  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConn;

    Q.SQL.Text :=
      'SELECT ' +
      '  ID, NUMMER, BEZEICHNUNG, ME_BEZ, VK_BRUTTO, WG, MWST_1, MWSTSATZ1 ' +
      'FROM VARTIKEL ' +
      'WHERE trim(cast(NUMMER as varchar(20))) = :PLU or trim(cast(ELENO as varchar(20))) = :PLU';

    Q.ParamByName('PLU').AsString := PLU;
    Q.Open;

    if not Q.IsEmpty then
    begin
      VatRate := VatRateFromFields(Q);
      Result :=
        '{' +
        '"ok":true,' +
        '"type":"plu",' +
        '"plu":"' + Q.FieldByName('NUMMER').AsString + '",' +
        '"name":"' + JsonEscape(Q.FieldByName('BEZEICHNUNG').AsString) + '",' +
        '"unit":"' + JsonEscape(Q.FieldByName('ME_BEZ').AsString) + '",' +
        '"ep":' + StringReplace(FloatToStr(Q.FieldByName('VK_BRUTTO').AsFloat), ',', '.', []) + ',' +
        '"vatRate":' + IntToStr(VatRate) + ',' +
        '"mwst":' + IntToStr(VatRate) + ',' +
        '"wg":' + Q.FieldByName('WG').AsString +
        '}';
    end;

  finally
    Q.Free;
  end;
end;

function TryConfiguredEANRule(const EAN, Rules: string; out PLU, ValueBlock: string;
  out IsPrice: Boolean): Boolean;
var
  Entries: TStringList;
  I, P, J: Integer;
  Entry, Prefix, Pattern, Data, NPart, PPart, GPart: string;
begin
  Result := False; PLU := ''; ValueBlock := ''; IsPrice := False;
  Entries := TStringList.Create;
  try
    Entries.StrictDelimiter := True; Entries.Delimiter := ';';
    Entries.DelimitedText := StringReplace(Rules, ',', ';', [rfReplaceAll]);
    for I := 0 to Entries.Count - 1 do
    begin
      Entry := Trim(Entries[I]); P := Pos('=', Entry);
      if P <= 1 then Continue;
      Prefix := Trim(Copy(Entry, 1, P - 1));
      Pattern := UpperCase(StringReplace(Trim(Copy(Entry, P + 1, MaxInt)), ' ', '', [rfReplaceAll]));
      if (Prefix = '') or (Copy(EAN, 1, Length(Prefix)) <> Prefix) then Continue;
      Data := Copy(EAN, Length(Prefix) + 1, Length(Pattern));
      if Length(Data) <> Length(Pattern) then Continue;
      NPart := ''; PPart := ''; GPart := '';
      for J := 1 to Length(Pattern) do
        case Pattern[J] of
          'N': NPart := NPart + Data[J];
          'P': PPart := PPart + Data[J];
          'G': GPart := GPart + Data[J];
        end;
      if (NPart = '') or ((PPart = '') and (GPart = '')) then Continue;
      PLU := IntToStr(StrToIntDef(NPart, 0));
      if PPart <> '' then begin ValueBlock := PPart; IsPrice := True; end
      else begin ValueBlock := GPart; IsPrice := False; end;
      Result := True; Exit;
    end;
  finally
    Entries.Free;
  end;
end;

function TSCOScanService.ScanEAN(const EAN: string): string;
var
  Kenner, PLU, Preis, StammJson: string;
  Kennzahl: Integer;
  IstPreisEAN, HasConfiguredRule: Boolean;
  Gewicht, EP, GP: Double;
  Q: TFDQuery;
  VatRate: Integer;
begin
  if Length(EAN) < 8 then
  begin
    Result := '{"ok":false,"message":"EAN zu kurz","ean":"' + EAN + '"}';
    Exit;
  end;

  StammJson := GetArtikelByEAN(EAN);
  if Pos('"ok":true', StammJson) > 0 then
  begin
    Result := StammJson;
    Exit;
  end;

  Kenner := Copy(EAN, 1, 2);
  Kennzahl := StrToIntDef(Kenner, -1);

  if Length(EAN) < 13 then
  begin
    Result := StammJson;
    Exit;
  end;

  HasConfiguredRule := TryConfiguredEANRule(EAN, SCOConfig.EANRules, PLU, Preis, IstPreisEAN);
  if not HasConfiguredRule then
  begin
    if (Kennzahl < 20) or (Kennzahl > 29) then
    begin
      Result := StammJson;
      Exit;
    end;
    IstPreisEAN := (Kennzahl mod 2) = 0;
    PLU := IntToStr(StrToIntDef(Copy(EAN, 3, 5), 0));
    Preis := Copy(EAN, 8, 5);
  end;

  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConn;
    Q.SQL.Text :=
      'SELECT NUMMER, BEZEICHNUNG, ME_BEZ, VK_BRUTTO, WG, MWST_1, MWSTSATZ1 ' +
      'FROM VARTIKEL ' +
      'WHERE trim(cast(NUMMER as varchar(20))) = :PLU or trim(cast(ELENO as varchar(20))) = :PLU';

    Q.ParamByName('PLU').AsString := PLU;
    Q.Open;

    if Q.IsEmpty then
    begin
      Result :=
        '{"ok":false,' +
        '"message":"PLU nicht gefunden",' +
        '"ean":"' + EAN + '",' +
        '"kenner":"' + Kenner + '",' +
        '"plu":"' + PLU + '",' +
        '"preisblock":"' + Preis + '"' +
        '}';
      Exit;
    end;

    EP := Q.FieldByName('VK_BRUTTO').AsFloat;
    VatRate := VatRateFromFields(Q);

    if IstPreisEAN then
    begin
      GP := StrToFloatDef(Preis, 0) / 100;
      if GP <= 0 then
      begin
        Result := '{"ok":false,"message":"Preis-EAN enthaelt keinen gueltigen Preis","plu":"' + PLU + '"}';
        Exit;
      end;
      if EP > 0 then
        Gewicht := GP / EP
      else
      begin
        Gewicht := 1;
        EP := GP;
      end;
    end
    else
    begin
      if EP <= 0 then
      begin
        Result := '{"ok":false,"message":"Artikel hat keinen gueltigen Preis","plu":"' + PLU + '"}';
        Exit;
      end;
      Gewicht := StrToFloatDef(Preis, 0) / 1000;
      GP := Gewicht * EP;
    end;

    Result :=
      '{' +
      '"ok":true,' +
      '"type":"scale",' +
      '"ean":"' + EAN + '",' +
      '"kenner":"' + Kenner + '",' +
      '"plu":"' + PLU + '",' +
      '"name":"' + JsonEscape(Q.FieldByName('BEZEICHNUNG').AsString) + '",' +
      '"unit":"' + JsonEscape(Q.FieldByName('ME_BEZ').AsString) + '",' +
      '"qty":' + StringReplace(FormatFloat('0.000', Gewicht), ',', '.', [rfReplaceAll]) + ',' +
      '"ep":' + StringReplace(FormatFloat('0.00', EP), ',', '.', [rfReplaceAll]) + ',' +
      '"gp":' + StringReplace(FormatFloat('0.00', GP), ',', '.', [rfReplaceAll]) + ',' +
      '"vatRate":' + IntToStr(VatRate) + ',' +
      '"mwst":' + IntToStr(VatRate) + ',' +
        '"wg":' + Q.FieldByName('WG').AsString +
        '}';

  finally
    Q.Free;
  end;
end;

end.








