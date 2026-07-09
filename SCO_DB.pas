unit SCO_DB;

interface

uses
  FireDAC.Comp.Client,
  FireDAC.Phys.FB,
  FireDAC.Comp.UI,
  Web.HTTPApp,
  System.Classes,
  data.db,
  System.SysUtils,
  System.SyncObjs;

var
  FB: TFDConnection;

procedure ConnectDB;
procedure EnterDBAccess;
procedure LeaveDBAccess;
function TestDBJson: string;
function GetGroupsJson: string;
function GetProductsJson(WG: Integer): string;
function JsonEscape(const S: string): string;
procedure SendProductImage(Response: TWebResponse; ArtikelID: Integer);

implementation

uses

  SCO_Config,
  FireDAC.Stan.Def,
  FireDAC.Stan.Intf,
  FireDAC.Phys,
  FireDAC.Phys.FBDef,
  FireDAC.VCLUI.Wait,
  SCO_Logger;

var
  FBDriverLink: TFDPhysFBDriverLink;
  FDWaitCursor: TFDGUIxWaitCursor;
  DBAccessLock: TCriticalSection;

function JsonEscape(const S: string): string;
begin
  Result := S;
  Result := StringReplace(Result, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
end;

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
function GetGroupsJson: string;
var
  Q: TFDQuery;
  First: Boolean;
  WG: Integer;
  WGBez: string;
begin
  Result := '[]';

  SCOConfig.Load;

  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'select NUMMER as WG, cast(coalesce(BEZEICHNUNG, '''') as varchar(100)) as WG_BEZ ' +
      'from GRUPPEN where NL_KEY = :NLKEY and NUMMER > 0 ' +
      'and coalesce(BEZEICHNUNG, '''') <> '''' order by BEZEICHNUNG';
    Q.ParamByName('NLKEY').AsInteger := SCOConfig.NLKey;

    Q.Open;

    Result := '[';
    First := True;

    while not Q.Eof do
    begin
      WG := Q.FieldByName('WG').AsInteger;
      WGBez := Q.FieldByName('WG_BEZ').AsString;

      if WGBez <> '' then
      begin
        if not First then
          Result := Result + ',';

        Result := Result +
          '{"id":' + IntToStr(WG) +
          ',"wg":' + IntToStr(WG) +
          ',"name":"' + JsonEscape(WGBez) + '"' +
          ',"icon":"??"}';

        First := False;
      end;

      Q.Next;
    end;

    Result := Result + ']';
  finally
    Q.Free;
  end;
end;

function GetProductsJson(WG: Integer): string;
var
  Q: TFDQuery;
  First: Boolean;
  Preis: Double;
  VatRate: Integer;
begin
  SCOConfig.Load;



  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'select first 20 ' +
      ' ID, cast(NUMMER as varchar(20)) as ELENO, VK_BRUTTO as PREIS, BEZEICHNUNG, BEZEICHNUNG2, ' +
      '  ME_BEZ, WG, WG_BEZ, MWST_1, MWSTSATZ1 ' +
      'from VARTIKEL ' +
      'where WG = :WG ' +
      'order by BEZEICHNUNG';

    Q.ParamByName('WG').AsInteger := WG;
    Q.Open;

    Result := '[';
    First := True;

    while not Q.Eof do
    begin
      if not First then
        Result := Result + ',';

      Preis := Q.FieldByName('PREIS').AsFloat;
      VatRate := VatRateFromFields(Q);

 Result := Result +
        '{' +
        '"id":' + Q.FieldByName('ID').AsString + ',' +
        '"image":"/api/productimage?id=' + Q.FieldByName('ID').AsString + '",' +
        '"group":' + Q.FieldByName('WG').AsString + ',' +
        '"plu":' + Trim(Q.FieldByName('ELENO').AsString) + ',' +
        '"name":"' + JsonEscape(Q.FieldByName('BEZEICHNUNG').AsString) + '",' +
        '"note":"' + JsonEscape(Q.FieldByName('BEZEICHNUNG2').AsString) + '",' +
        '"unit":"' + JsonEscape(Q.FieldByName('ME_BEZ').AsString) + '",' +
        '"wg":' + Q.FieldByName('WG').AsString + ',' +
        '"price":' + StringReplace(FormatFloat('0.00', Preis), ',', '.', [rfReplaceAll]) + ',' +
        '"ep":' + StringReplace(FormatFloat('0.00', Preis), ',', '.', [rfReplaceAll]) + ',' +
        '"vatRate":' + IntToStr(VatRate) + ',' +
        '"mwst":' + IntToStr(VatRate) +
        '}';

      First := False;
      Q.Next;
    end;

    Result := Result + ']';
  finally
    Q.Free;
  end;
end;


procedure SendProductImage(Response: TWebResponse; ArtikelID: Integer);
var
  Q: TFDQuery;
  Stream: TMemoryStream;
  BlobStream: TStream;
begin
  Q := TFDQuery.Create(nil);
  Stream := TMemoryStream.Create;
  BlobStream := nil;
  try
    Q.Connection := FB;
    Q.SQL.Text :=
      'select first 1 BILD ' +
      'from PRODUKT_BILDER ' +
      'where ID = :ID ' +
      'and BILD is not null ' +
      'order by LFDNO';

    Q.ParamByName('ID').AsInteger := ArtikelID;
    Q.Open;

    if Q.IsEmpty then
    begin
      Response.StatusCode := 404;
      Response.ContentType := 'text/plain; charset=utf-8';
      Response.Content := 'Bild nicht gefunden';
      Exit;
    end;

    BlobStream := Q.CreateBlobStream(Q.FieldByName('BILD'), bmRead);
    try
      Stream.CopyFrom(BlobStream, 0);
    finally
      BlobStream.Free;
      BlobStream := nil;
    end;

    Stream.Position := 0;

        if Stream.Size >= 8 then
        begin
          if (PByte(Stream.Memory)^ = $89) then
            Response.ContentType := 'image/png'
          else if (PByte(Stream.Memory)^ = $FF) then
            Response.ContentType := 'image/jpeg'
          else
            Response.ContentType := 'application/octet-stream';
        end
        else
          Response.ContentType := 'application/octet-stream';


    Response.ContentStream := Stream;
    Stream := nil; // Response �bernimmt den Stream
  finally
    BlobStream.Free;
    Stream.Free;
    Q.Free;
  end;
end;

procedure ResolveDatabaseParams(out Host, DatabaseName: string; out Port: Integer);
var P, SlashPos: Integer; Prefix: string;
begin
  SCOConfig.Load;
  Host := Trim(SCOConfig.DBHost);
  if Host = '' then Host := 'localhost';
  Port := SCOConfig.DBPort;
  if Port <= 0 then Port := 3050;
  DatabaseName := Trim(SCOConfig.DBFirebird);

  // Rueckwaertskompatibel: 192.168.1.10/3050:C:\Daten\Foodware.fdb
  P := Pos(':', DatabaseName);
  if P > 2 then
  begin
    Prefix := Copy(DatabaseName, 1, P - 1);
    if (Pos('\', Prefix) = 0) and (Pos(':', Prefix) = 0) then
    begin
      SlashPos := Pos('/', Prefix);
      if SlashPos > 0 then
      begin
        Port := StrToIntDef(Copy(Prefix, SlashPos + 1, MaxInt), Port);
        Prefix := Copy(Prefix, 1, SlashPos - 1);
      end;
      if Trim(Prefix) <> '' then Host := Trim(Prefix);
      DatabaseName := Copy(DatabaseName, P + 1, MaxInt);
    end;
  end;
end;

procedure ConnectDBInternal;
var Host, DatabaseName, VendorLib: string; Port: Integer;
begin
  if Assigned(FB) and FB.Connected then Exit;
  ResolveDatabaseParams(Host, DatabaseName, Port);
  if DatabaseName = '' then
    raise Exception.Create('Firebird-Datenbank ist nicht konfiguriert.');

  if not Assigned(FBDriverLink) then
  begin
    FBDriverLink := TFDPhysFBDriverLink.Create(nil);
    VendorLib := ExtractFilePath(ParamStr(0)) + 'fbclient.dll';
    if FileExists(VendorLib) then FBDriverLink.VendorLib := VendorLib;
  end;
  if not Assigned(FDWaitCursor) then
  begin
    FDWaitCursor := TFDGUIxWaitCursor.Create(nil);
    FDWaitCursor.Provider := 'Forms';
  end;
  if not Assigned(FB) then FB := TFDConnection.Create(nil);

  FB.Connected := False;
  FB.LoginPrompt := False;
  FB.Params.Clear;
  FB.Params.Add('DriverID=FB');
  FB.Params.Add('Protocol=TCPIP');
  FB.Params.Add('Server=' + Host);
  FB.Params.Add('Port=' + IntToStr(Port));
  FB.Params.Add('Database=' + DatabaseName);
  FB.Params.Add('User_Name=' + SCOConfig.DBUser);
  FB.Params.Add('Password=' + SCOConfig.DBPassword);
  FB.Params.Add('CharacterSet=' + SCOConfig.DBCharset);
  FB.Params.Add('SQLDialect=3');
  LogTransaction('FIREBIRD CONNECT host=' + Host + ' port=' + IntToStr(Port) + ' database=' + DatabaseName);
  try
    FB.Connected := True;
    LogTransaction('FIREBIRD CONNECT OK host=' + Host + ' database=' + DatabaseName);
  except
    on E: Exception do
    begin
      LogError('FIREBIRD CONNECT ERROR host=' + Host + ' port=' + IntToStr(Port) +
        ' database=' + DatabaseName + ' class=' + E.ClassName + ' message=' + E.Message);
      raise;
    end;
  end;
end;

procedure EnterDBAccess;
begin
  DBAccessLock.Acquire;
end;

procedure LeaveDBAccess;
begin
  DBAccessLock.Release;
end;

procedure ConnectDB;
begin
  EnterDBAccess;
  try
    ConnectDBInternal;
  finally
    LeaveDBAccess;
  end;
end;

function TestDBJson: string;
var Q: TFDQuery; Host, DatabaseName: string; Port: Integer;
begin
  try
    if Assigned(FB) then FB.Connected := False;
    ConnectDB;
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := FB;
      Q.SQL.Text := 'select current_timestamp as SERVERZEIT from RDB$DATABASE';
      Q.Open;
      ResolveDatabaseParams(Host, DatabaseName, Port);
      Result := '{"ok":true,"message":"Firebird-Verbindung erfolgreich.","host":"' +
        JsonEscape(Host) + '","port":' + IntToStr(Port) + ',"database":"' +
        JsonEscape(DatabaseName) + '","serverTime":"' +
        FormatDateTime('yyyy-mm-dd hh:nn:ss', Q.FieldByName('SERVERZEIT').AsDateTime) + '"}';
    finally Q.Free; end;
  except
    on E: Exception do
      Result := '{"ok":false,"message":"' + JsonEscape(E.Message) + '"}';
  end;
end;
initialization
  DBAccessLock := TCriticalSection.Create;

finalization
  FreeAndNil(FB);
  FreeAndNil(FBDriverLink);
  FreeAndNil(FDWaitCursor);
  FreeAndNil(DBAccessLock);

end.





