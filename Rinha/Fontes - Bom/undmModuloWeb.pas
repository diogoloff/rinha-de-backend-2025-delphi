unit undmModuloWeb;

interface

uses
  System.SysUtils, System.Classes, System.Json, System.DateUtils,
  Web.HTTPApp, Web.WebFileDispatcher, Web.HTTPProd,
  Datasnap.DSHTTPCommon, Datasnap.DSHTTPWebBroker, Datasnap.DSServer,
  DataSnap.DSAuth, Datasnap.DSProxyJavaScript, IPPeerServer, Datasnap.DSMetadata, Datasnap.DSServerMetadata,
  Datasnap.DSClientMetadata, Datasnap.DSCommonServer, Datasnap.DSHTTP,
  unRequisicaoPendente, unSchedulerHelper;

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
    FromParam, ToParam: string;
begin
    Pagamentos := TsmPagamentos.Create(nil);
    try
        // Extrai os parâmetros da URL
        FromParam := Request.QueryFields.Values['from'];
        ToParam := Request.QueryFields.Values['to'];

        Response.Content := Pagamentos.ObterResumoPagamentos(FromParam, ToParam);
        Response.ContentType := 'application/json';
        Handled := True;
    finally
        Pagamentos.Free;
    end;
end;

procedure TdmModuloWeb.dmModuloWebPaymentsAction(Sender: TObject; Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
var
    //Pagamentos: TsmPagamentos;
    ljObj: TJSONObject;
    correlationId: string;
    amount: Double;
    requestedAt: string;
    ltReq: TRequisicaoPendente;
begin
    {Pagamentos := TsmPagamentos.Create(nil);
    try
        Response.Content := Pagamentos.EnviarPagamento(Request.Content);
        Response.ContentType := 'application/json';
        Handled := True;
    finally
        Pagamentos.Free;
    end; }

    ljObj := nil;
    try
        ljObj := TJSONObject.ParseJSONValue(Request.Content) as TJSONObject;
        correlationId := ljObj.GetValue('correlationId').Value;
        amount := StrToFloat(ljObj.GetValue('amount').Value);
        requestedAt := DateToISO8601(Now, True);
    finally
        ljObj.Free;
    end;

    ltReq := TRequisicaoPendente.Create(correlationId, amount, requestedAt);

    // Antes de adicionar o worker talvez seria importante ver quantos itens tem na fila e de alguma forma gerar uma espécie de timeout
    // minimo para segurar as novas requisições até a fila aliviar novamente

    //LiberaCarga;

    //AdicionarWorker(ltReq);
    AdicionarWorkerProcessamento(ltReq);
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

