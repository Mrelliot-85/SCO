unit SCO_RFIDTcpService;

interface

uses
  System.SysUtils;

procedure StartRFIDTcpService;
procedure StopRFIDTcpService;
procedure RestartRFIDTcpService;
procedure ClearRFIDTcpEvents;
function RFIDTcpEventsJson(AfterId: Integer): string;

implementation

uses
  System.Classes,
  System.SyncObjs,
  System.StrUtils,
  Winapi.Windows,
  IdContext,
  IdGlobal,
  IdTCPClient,
  IdTCPServer,
  SCO_CONFIG,
  SCO_Logger;

type
  TRFIDTcpService = class
  private
    FServer: TIdTCPServer;
    FClientThread: TThread;
    FLock: TCriticalSection;
    FEvents: TStringList;
    FNextId: Integer;
    FLastTag: string;
    FLastAntenna: Integer;
    FLastTick: Cardinal;
    FLastClientError: string;
    FLastClientErrorTick: Cardinal;
    FStopping: Boolean;
    procedure OnExecute(AContext: TIdContext);
    procedure StartClient(const Host: string; Port: Integer);
    procedure StartServer(const BindIP: string; Port: Integer);
    procedure ProcessLine(const Line: string);
    procedure QueueEvent(Status, Antenna: Integer; const Tag, RawLine: string);
    function ParseLine(const Line: string; out Status, Antenna: Integer; out Tag: string): Boolean;
    function JS(const S: string): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    procedure ClearEvents;
    function EventsJson(AfterId: Integer): string;
  end;

var
  RFIDService: TRFIDTcpService;

function TRFIDTcpService.JS(const S: string): string;
begin
  Result := S;
  Result := StringReplace(Result, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '"', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
end;

constructor TRFIDTcpService.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FEvents := TStringList.Create;
  FNextId := 1;
  FServer := TIdTCPServer.Create(nil);
  FServer.OnExecute := OnExecute;
end;

destructor TRFIDTcpService.Destroy;
begin
  Stop;
  FServer.Free;
  FEvents.Free;
  FLock.Free;
  inherited Destroy;
end;

function TRFIDTcpService.ParseLine(const Line: string; out Status, Antenna: Integer; out Tag: string): Boolean;
var
  Parts: TArray<string>;
begin
  Result := False;
  Status := 0;
  Antenna := 0;
  Tag := '';
  Parts := Line.Trim.Split([';']);
  if Length(Parts) < 3 then
    Exit;
  Status := StrToIntDef(Trim(Parts[0]), 0);
  Antenna := StrToIntDef(Trim(Parts[1]), 0);
  Tag := UpperCase(Trim(Parts[2]));
  Tag := StringReplace(Tag, #13, '', [rfReplaceAll]);
  Tag := StringReplace(Tag, #10, '', [rfReplaceAll]);
  Result := (Status > 0) and (Antenna > 0) and (Tag <> '');
end;

procedure TRFIDTcpService.ProcessLine(const Line: string);
var
  CleanLine, Tag: string;
  Status, Antenna: Integer;
begin
  CleanLine := Trim(Line);
  if CleanLine = '' then
    Exit;

  if ParseLine(CleanLine, Status, Antenna, Tag) then
    QueueEvent(Status, Antenna, Tag, CleanLine)
  else
    LogError('RFID TCP PARSE FEHLER: ' + CleanLine);
end;

procedure TRFIDTcpService.QueueEvent(Status, Antenna: Integer; const Tag, RawLine: string);
var
  Tick: Cardinal;
  Item: string;
begin
  Tick := GetTickCount;
  if (Status = 1) and SameText(Tag, FLastTag) and (Antenna = FLastAntenna) and (Tick - FLastTick < 5000) then
  begin
    Exit;
  end;

  FLastTag := Tag;
  FLastAntenna := Antenna;
  FLastTick := Tick;

  if Status <> 1 then
  begin
    Exit;
  end;

  FLock.Enter;
  try
    Item :=
      '{"id":' + IntToStr(FNextId) +
      ',"status":' + IntToStr(Status) +
      ',"antenna":' + IntToStr(Antenna) +
      ',"tag":"' + JS(Tag) + '"' +
      ',"raw":"' + JS(RawLine) + '"}';
    FEvents.AddObject(Item, TObject(FNextId));
    Inc(FNextId);
    while FEvents.Count > 100 do
      FEvents.Delete(0);
  finally
    FLock.Leave;
  end;
end;

procedure TRFIDTcpService.OnExecute(AContext: TIdContext);
begin
  try
    ProcessLine(AContext.Connection.IOHandler.ReadLn(IndyTextEncoding_UTF8));
  except
    on E: Exception do
      LogError('RFID TCP SERVER READ FEHLER: ' + E.ClassName + ' - ' + E.Message);
  end;
end;

procedure TRFIDTcpService.StartClient(const Host: string; Port: Integer);
begin
  if Assigned(FClientThread) then
    Exit;

  FStopping := False;
  FClientThread := TThread.CreateAnonymousThread(
    procedure
    var
      TCP: TIdTCPClient;
      Line: string;
    begin
      TCP := TIdTCPClient.Create(nil);
      try
        TCP.Host := Host;
        TCP.Port := Port;
        TCP.ConnectTimeout := 3000;
        TCP.ReadTimeout := 1000;

        while not FStopping and not TThread.CurrentThread.CheckTerminated do
        begin
          try
            if not TCP.Connected then
            begin
              LogTransaction('RFID TCP CLIENT CONNECT host=' + Host + ' port=' + IntToStr(Port));
              TCP.Connect;
              LogTransaction('RFID TCP CLIENT CONNECTED host=' + Host + ' port=' + IntToStr(Port));
            end;

            Line := TCP.IOHandler.ReadLn(IndyTextEncoding_UTF8);
            ProcessLine(Line);
          except
            on E: Exception do
            begin
              if not FStopping then
              begin
                if (FLastClientError <> E.Message) or (GetTickCount - FLastClientErrorTick > 30000) then
                begin
                  FLastClientError := E.Message;
                  FLastClientErrorTick := GetTickCount;
                  LogError('RFID TCP CLIENT FEHLER: ' + E.ClassName + ' - ' + E.Message);
                end;
              end;
              try
                if TCP.Connected then
                  TCP.Disconnect;
              except
              end;
              if not FStopping then
                Sleep(1500);
            end;
          end;
        end;
      finally
        try
          if TCP.Connected then
            TCP.Disconnect;
        except
        end;
        TCP.Free;
      end;
    end
  );
  FClientThread.FreeOnTerminate := False;
  FClientThread.Start;
  LogTransaction('RFID TCP CLIENT START host=' + Host + ' port=' + IntToStr(Port));
end;

procedure TRFIDTcpService.StartServer(const BindIP: string; Port: Integer);
begin
  if FServer.Active then
    Exit;
  try
    FServer.Bindings.Clear;
    with FServer.Bindings.Add do
    begin
      IP := BindIP;
      Port := Port;
    end;
    FServer.Active := True;
    LogTransaction('RFID TCP SERVER ACTIVE ip=' + BindIP + ' port=' + IntToStr(Port));
  except
    on E: Exception do
      LogError('RFID TCP SERVER START FEHLER: ' + E.ClassName + ' - ' + E.Message);
  end;
end;

procedure TRFIDTcpService.Start;
var
  Host, BindIP: string;
  Port: Integer;
begin
  SCOConfig.Load;
  if not SCOConfig.RFIDAktiv then
  begin
    LogTransaction('RFID TCP nicht gestartet: RFID deaktiviert');
    Exit;
  end;

  Port := SCOConfig.RFIDTCPPort;
  if Port <= 0 then
  begin
    LogTransaction('RFID TCP nicht gestartet: TCPPort nicht konfiguriert');
    Exit;
  end;

  Host := Trim(SCOConfig.RFIDHost);
  if Host <> '' then
  begin
    StartClient(Host, Port);
    Exit;
  end;

  BindIP := Trim(SCOConfig.RFIDBindIP);
  if BindIP = '' then
    BindIP := '0.0.0.0';
  StartServer(BindIP, Port);
end;

procedure TRFIDTcpService.Stop;
begin
  FStopping := True;
  if Assigned(FClientThread) then
  begin
    FClientThread.Terminate;
    FClientThread.WaitFor;
    FreeAndNil(FClientThread);
    LogTransaction('RFID TCP CLIENT STOP');
  end;

  if Assigned(FServer) and FServer.Active then
  begin
    FServer.Active := False;
    FServer.Bindings.Clear;
    LogTransaction('RFID TCP SERVER STOP');
  end;
end;

procedure TRFIDTcpService.ClearEvents;
begin
  FLock.Enter;
  try
    FEvents.Clear;
    FNextId := 1;
    FLastTag := '';
    FLastAntenna := 0;
    FLastTick := 0;
  finally
    FLock.Leave;
  end;
end;
function TRFIDTcpService.EventsJson(AfterId: Integer): string;
var
  I, Id: Integer;
  First: Boolean;
begin
  Result := '{"ok":true,"events":[';
  First := True;
  FLock.Enter;
  try
    for I := 0 to FEvents.Count - 1 do
    begin
      Id := Integer(FEvents.Objects[I]);
      if Id <= AfterId then
        Continue;
      if not First then
        Result := Result + ',';
      Result := Result + FEvents[I];
      First := False;
    end;
  finally
    FLock.Leave;
  end;
  Result := Result + ']}';
end;

procedure StartRFIDTcpService;
begin
  if not Assigned(RFIDService) then
    RFIDService := TRFIDTcpService.Create;
  RFIDService.ClearEvents;
  RFIDService.Start;
end;

procedure StopRFIDTcpService;
begin
  if Assigned(RFIDService) then
    RFIDService.Stop;
end;

procedure RestartRFIDTcpService;
begin
  if not Assigned(RFIDService) then
    RFIDService := TRFIDTcpService.Create;
  RFIDService.Stop;
  RFIDService.ClearEvents;
  RFIDService.Start;
end;

procedure ClearRFIDTcpEvents;
begin
  if Assigned(RFIDService) then
    RFIDService.ClearEvents;
end;

function RFIDTcpEventsJson(AfterId: Integer): string;
begin
  if not Assigned(RFIDService) then
    RFIDService := TRFIDTcpService.Create;
  Result := RFIDService.EventsJson(AfterId);
end;

initialization
  RFIDService := nil;

finalization
  RFIDService.Free;

end.






