unit SCO_Start;
interface
uses
  Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.AppEvnts, Vcl.StdCtrls, IdHTTPWebBrokerBridge, IdGlobal, Web.HTTPApp,
  Vcl.ExtCtrls;
type
  TForm1 = class(TForm)
    ButtonStart: TButton;
    ButtonStop: TButton;
    EditPort: TEdit;
    Label1: TLabel;
    ApplicationEvents1: TApplicationEvents;
    ButtonOpenBrowser: TButton;
    ButtonOpenSCO: TButton;
    ButtonOpenAdmin: TButton;
    ButtonOpenLabeling: TButton;
    ButtonOpenStats: TButton;
    ButtonOpenHelp: TButton;
    TrayIcon1: TTrayIcon;
    procedure DailyCloseTimerTimer(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure ApplicationEvents1Idle(Sender: TObject; var Done: Boolean);
    procedure ButtonStartClick(Sender: TObject);
    procedure ButtonStopClick(Sender: TObject);
    procedure ButtonOpenBrowserClick(Sender: TObject);
    procedure ButtonOpenSCOClick(Sender: TObject);
    procedure ButtonOpenAdminClick(Sender: TObject);
    procedure ButtonOpenLabelingClick(Sender: TObject);
    procedure ButtonOpenStatsClick(Sender: TObject);
    procedure ButtonOpenHelpClick(Sender: TObject);
  private
    FServer: TIdHTTPWebBrokerBridge;
    FDailyCloseTimer: TTimer;
    procedure StartServer;
    procedure InitCashLogyAsync;
    procedure OpenModule(const Path: string);
    { Private-Deklarationen }
  public
    { Public-Deklarationen }
  end;
var
  Form1: TForm1;
implementation
{$R *.dfm}
uses
  WinApi.Windows, Winapi.ShellApi, IdTCPClient, SCO_Config,SCO_CashLogyService, SCO_Logger, SCO_RFIDTcpService, SCO_DailyCloseService;
function CashLogyConnectorWindowOpen: Boolean;
begin
  Result := FindWindow(nil, 'CashlogyConnector') <> 0;
end;
function CashLogyPortOpen(const Host: string; Port: Integer): Boolean;
var
  TCP: TIdTCPClient;
  H: string;
begin
  Result := False;
  H := Trim(Host);
  if H = '' then
    H := '127.0.0.1';
  if Port <= 0 then
    Exit;
  TCP := TIdTCPClient.Create(nil);
  try
    TCP.Host := H;
    TCP.Port := Port;
    TCP.ConnectTimeout := 700;
    TCP.ReadTimeout := 700;
    try
      TCP.Connect;
      Result := True;
    except
      Result := False;
    end;
  finally
    if TCP.Connected then
      TCP.Disconnect;
    TCP.Free;
  end;
end;
procedure TForm1.ApplicationEvents1Idle(Sender: TObject; var Done: Boolean);
begin
  ButtonStart.Enabled := not FServer.Active;
  ButtonStop.Enabled := FServer.Active;
  EditPort.Enabled := not FServer.Active;
end;
procedure TForm1.OpenModule(const Path: string);
var
  LURL: string;
begin
  StartServer;
  LURL := Format('http://localhost:%s%s', [EditPort.Text, Path]);
  ShellExecute(0, nil, PChar(LURL), nil, nil, SW_SHOWNOACTIVATE);
end;
procedure TForm1.ButtonOpenSCOClick(Sender: TObject);
begin
  OpenModule('/sco/');
end;
procedure TForm1.ButtonOpenAdminClick(Sender: TObject);
begin
  OpenModule('/admin/');
end;
procedure TForm1.ButtonOpenLabelingClick(Sender: TObject);
begin
  OpenModule('/labeling/');
end;
procedure TForm1.ButtonOpenStatsClick(Sender: TObject);
begin
  OpenModule('/statistik/');
end;
procedure TForm1.ButtonOpenHelpClick(Sender: TObject);
begin
  OpenModule('/help/');
end;
procedure TForm1.ButtonOpenBrowserClick(Sender: TObject);
var
  LURL: string;
begin
  StartServer;
  LURL := Format('http://localhost:%s', [EditPort.Text]);
  ShellExecute(0,
        nil,
        PChar(LURL), nil, nil, SW_SHOWNOACTIVATE);
end;
procedure TForm1.ButtonStartClick(Sender: TObject);
begin
  StartServer;
end;
procedure TForm1.ButtonStopClick(Sender: TObject);
begin
  StopRFIDTcpService;
  FServer.Active := False;
  FServer.Bindings.Clear;
end;
procedure TForm1.FormCreate(Sender: TObject);
begin
  FServer := TIdHTTPWebBrokerBridge.Create(Self);
  SCOConfig.Load;
  EditPort.Text := IntToStr(SCOConfig.Port);
  StartServer;
  InitCashLogyAsync;
  FDailyCloseTimer := TTimer.Create(Self);
  FDailyCloseTimer.Interval := 60000;
  FDailyCloseTimer.OnTimer := DailyCloseTimerTimer;
  FDailyCloseTimer.Enabled := True;
end;

procedure TForm1.DailyCloseTimerTimer(Sender: TObject);
begin
  FDailyCloseTimer.Enabled := False;
  try
    CheckScheduledDailyClose;
  finally
    FDailyCloseTimer.Enabled := True;
  end;
end;

procedure TForm1.InitCashLogyAsync;
var
  Host: string;
  Port: Integer;
  ExeName: string;
begin
  SCOConfig.Load;
  if not SCOConfig.PaymentBar then
  begin
    LogPayment('CashLogy Init übersprungen: Barzahlung nicht aktiv');
    Exit;
  end;
  Host := SCOConfig.CashLogyConnectorHost;
  Port := SCOConfig.CashLogyConnectorPort;
  ExeName := SCOConfig.CashLogyConnectorExe;
  TThread.CreateAnonymousThread(
    procedure
    var
      Cash: TCashLogyService;
      R: TCashLogyResult;
    begin
      try
        LogPayment('CashLogy Init Start Host=' + Host + ' Port=' + IntToStr(Port));
        if CashLogyConnectorWindowOpen then
          LogPayment('CashLogy Connector Fenster bereits aktiv')
        else if CashLogyPortOpen(Host, Port) then
          LogPayment('CashLogy Connector bereits aktiv Host=' + Host + ' Port=' + IntToStr(Port))
        else if Trim(ExeName) <> '' then
        begin
          if FileExists(ExeName) then
          begin
            ShellExecute(0, nil, PChar(ExeName), nil,
              PChar(ExtractFilePath(ExeName)), SW_SHOWNORMAL);
            LogPayment('CashLogy Connector Start versucht: ' + ExeName);
            Sleep(1500);
          end
          else
            LogError('CashLogy Connector EXE nicht gefunden: ' + ExeName);
        end;
        Cash := TCashLogyService.Create(Host, Port);
        try
          R := Cash.Init;
          if R.OK then
            LogPayment('CashLogy Init OK: ' + R.StatusText)
          else
            LogError('CashLogy Init FEHLER: ' + R.StatusText);
        finally
          Cash.Free;
        end;
      except
        on E: Exception do
          LogError('CashLogy Init Exception: ' + E.ClassName + ' - ' + E.Message);
      end;
    end
  ).Start;
end;
procedure TForm1.StartServer;
begin
  if not FServer.Active then
  begin
    try
      LogTransaction('WEB SERVER START port=' + EditPort.Text);
      FServer.Bindings.Clear;
      FServer.DefaultPort := StrToInt(EditPort.Text);
      with FServer.Bindings.Add do
      begin
        IP := '0.0.0.0'; // wichtig: nicht nur localhost
        Port := StrToInt(EditPort.Text);
      end;
      FServer.Active := True;
      LogTransaction('WEB SERVER ACTIVE port=' + EditPort.Text);
      SCOConfig.Load;
      if SCOConfig.RFIDAktiv then
        StartRFIDTcpService
      else
        StopRFIDTcpService;
    except
      on E: Exception do
      begin
        LogError('WEB SERVER START FEHLER: ' + E.ClassName + ' - ' + E.Message);
        raise;
      end;
    end;
  end
  else
    LogTransaction('WEB SERVER ALREADY ACTIVE port=' + EditPort.Text);
end;
end.






