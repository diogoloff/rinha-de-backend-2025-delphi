unit undmModuloWeb;

interface

uses
  System.SysUtils, System.Classes, System.Json,
  Web.HTTPApp, Web.WebFileDispatcher, Web.HTTPProd,
  Datasnap.DSHTTPCommon, Datasnap.DSHTTPWebBroker, Datasnap.DSServer,
  DataSnap.DSAuth, Datasnap.DSProxyJavaScript, IPPeerServer, Datasnap.DSMetadata, Datasnap.DSServerMetadata,
  Datasnap.DSClientMetadata, Datasnap.DSCommonServer, Datasnap.DSHTTP;

type
  TdmModuloWeb = class(TWebModule)
    DSRESTWebDispatcher1: TDSRESTWebDispatcher;
    procedure WebModule1DefaultHandlerAction(Sender: TObject;
      Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
    procedure WebModuleCreate(Sender: TObject);
    procedure dmModuloWebPaymentsAction(Sender: TObject; Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
    procedure dmModuloWebObterResumoPagamentosAction(Sender: TObject; Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
    procedure WebModuleAfterDispatch(Sender: TObject; Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
    procedure WebModuleBeforeDispatch(Sender: TObject; Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  WebModuleClass: TComponentClass = TdmModuloWeb;

implementation

{%CLASSGROUP 'System.Classes.TPersistent'}

{$R *.dfm}

uses unsmPagamentos, undmServer, Web.WebReq;

procedure TdmModuloWeb.dmModuloWebObterResumoPagamentosAction(Sender: TObject; Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
var
    Pagamentos: TsmPagamentos;
    lsFromParam, lsToParam: string;
begin
    Pagamentos := TsmPagamentos.Create(nil);
    try
        lsFromParam := Request.QueryFields.Values['from'];
        lsToParam := Request.QueryFields.Values['to'];

        Response.Content := Pagamentos.ObterResumoPagamentos(lsFromParam, lsToParam);
        Response.ContentType := 'application/json';
        Handled := True;
    finally
        Pagamentos.Free;
    end;
end;

procedure TdmModuloWeb.dmModuloWebPaymentsAction(Sender: TObject; Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
var
    Pagamentos: TsmPagamentos;
begin
    Pagamentos := TsmPagamentos.Create(nil);
    try
        Pagamentos.EnviarPagamento(Request.Content);
        //Response.Content := Pagamentos.EnviarPagamento(Request.Content);
        //Response.ContentType := 'application/json';
        Handled := True;
    finally
        Pagamentos.Free;
    end;
end;

procedure TdmModuloWeb.WebModule1DefaultHandlerAction(Sender: TObject;
  Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
begin
    Response.Content :=
        '<html>' +
        '<head><title>DataSnap Server</title></head>' +
        '<body>DataSnap Server</body>' +
        '</html>';
end;

procedure TdmModuloWeb.WebModuleAfterDispatch(Sender: TObject; Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
var
    CodePos: Integer;
begin
    CodePos := Pos('"code":400', Response.Content);
    if CodePos > 0 then
        Response.StatusCode := 400
    else
    begin
        CodePos := Pos('"code":500', Response.Content);
        if CodePos > 0 then
            Response.StatusCode := 500;
    end;
end;

procedure TdmModuloWeb.WebModuleBeforeDispatch(Sender: TObject; Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
begin
    Response.ContentType := 'application/json; charset=utf-8';
end;

procedure TdmModuloWeb.WebModuleCreate(Sender: TObject);
begin
    DSRESTWebDispatcher1.Server := DSServer;
    if DSServer.Started then
    begin
        DSRESTWebDispatcher1.DbxContext := DSServer.DbxContext;
        DSRESTWebDispatcher1.Start;
    end;
end;

initialization

finalization
    Web.WebReq.FreeWebModules;

end.

