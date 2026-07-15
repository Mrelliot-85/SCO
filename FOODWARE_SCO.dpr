program FOODWARE_SCO;
{$APPTYPE GUI}

uses
  System.SysUtils,
  System.IOUtils,
  Vcl.Forms,
  Web.WebReq,
  IdHTTPWebBrokerBridge,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Factory,
  FireDAC.Stan.Util,
  FireDAC.UI.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  FireDAC.Phys.FB,
  FireDAC.Phys.FBDef,
  FireDAC.VCLUI.Wait,
  FireDAC.Comp.UI,
  FireDAC.DatS,
  FireDAC.DApt.Intf,
  FireDAC.DApt,
  FireDAC.Comp.DataSet,
  FireDAC.Comp.Client,
  SCO_Start in 'SCO_Start.pas' {Form1},
  SCO_WEBMODUL in 'SCO_WEBMODUL.pas' {WebModule1: TWebModule},
  SCO_CONFIG in 'SCO_CONFIG.pas',
  SCO_ScanService in 'SCO_ScanService.pas',
  SCO_DB in 'SCO_DB.pas',
  SCO_Logger in 'SCO_Logger.pas',
  SCO_PaymentService in 'SCO_PaymentService.pas',
  SCO_CashLogyService in 'SCO_CashLogyService.pas',
  SCO_LabelingService in 'SCO_LabelingService.pas',
  SCO_LabelDesignerService in 'SCO_LabelDesignerService.pas',
  SCO_ScaleService in 'SCO_ScaleService.pas',
  SCO_SalesJournalService in 'SCO_SalesJournalService.pas',
  SCO_LocalEventService in 'SCO_LocalEventService.pas',
  SCO_StatisticsService in 'SCO_StatisticsService.pas',
  SCO_DailyCloseService in 'SCO_DailyCloseService.pas',
  SCO_ESLService in 'SCO_ESLService.pas',
  SCO_RFIDTcpService in 'SCO_RFIDTcpService.pas',
  URFIDReaderService in 'URFIDReaderService.pas';
 // URFIDConnect in 'URFIDConnect.pas' {Form2};

{$R *.res}

begin
  try
    if WebRequestHandler <> nil then
      WebRequestHandler.WebModuleClass := WebModuleClass;
    Application.Initialize;
    Application.CreateForm(TForm1, Form1);
   // Application.CreateForm(TForm2, Form2);
    Application.Run;
  except
    on E: Exception do
    begin
      TFile.WriteAllText(ExtractFilePath(ParamStr(0)) + 'startup_error.log',
        FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' ' + E.ClassName + ': ' + E.Message,
        TEncoding.UTF8);
      raise;
    end;
  end;
end.




