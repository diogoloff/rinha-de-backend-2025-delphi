unit undmServer;

interface

uses System.SysUtils, System.Classes, System.IOUtils, System.SyncObjs, System.DateUtils, System.Json,
  Datasnap.DSServer, Datasnap.DSCommonServer, Datasnap.DSAuth, Datasnap.DSSession,
  IPPeerServer, IPPeerAPI, IdHTTPWebBrokerBridge, FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.UI.Intf, FireDAC.Phys.Intf,
  FireDAC.Stan.Def, FireDAC.Phys, FireDAC.Comp.Client, FireDAC.ConsoleUI.Wait, FireDAC.Phys.FBDef, FireDAC.Phys.IBBase, FireDAC.Phys.FB, FireDAC.Comp.UI,
  IdBaseComponent, IdComponent, IdTCPConnection, IdTCPClient, IdHTTP, System.Generics.Collections, FireDAC.Stan.Param, FireDAC.DatS, FireDAC.DApt.Intf,
  FireDAC.Stan.Async, FireDAC.DApt, Data.DB, FireDAC.Comp.DataSet,
  unGenerica, unConstantes, unWorkerHelper, unDBHelper, unHealthHelper, unSchedulerHelper;

type
    TdmServer = class(TDataModule)
        DSServer: TDSServer;
        DSServerPagamentos: TDSServerClass;
        FDManagerRinha: TFDManager;
        FDGUIxWaitCursor1: TFDGUIxWaitCursor;
        FDPhysFBDriverLink1: TFDPhysFBDriverLink;
        procedure DSServerPagamentosGetClass(DSServerClass: TDSServerClass;
          var PersistentClass: TPersistentClass);
        procedure DataModuleCreate(Sender: TObject);
    procedure DataModuleDestroy(Sender: TObject);
    private
        FMonitoramentoAtivo: Boolean;

        procedure PreparaConexaoBanco;

      { Private declarations }
    public
        constructor Create(AOwner: TComponent); override;
        destructor Destroy; override;
    end;

    function DSServer: TDSServer;

    procedure ExcluirRegistros;
    procedure TerminateThreads;
    procedure RunDSServer(const AServer: TIdHTTPWebBrokerBridge);
    procedure StopServer(const AServer: TIdHTTPWebBrokerBridge);

var
    FModule: TComponent;
    FDSServer: TDSServer;

implementation

{%CLASSGROUP 'System.Classes.TPersistent'}

{$R *.dfm}

uses unsmPagamentos;

function DSServer: TDSServer;
begin
    Result := FDSServer;
end;

constructor TdmServer.Create(AOwner: TComponent);
begin
    inherited;
    FDSServer := DSServer;
end;

procedure TdmServer.PreparaConexaoBanco;
var
    oParams: TStringList;
begin
    FDManager.Active := False;

    oParams := ParametrosBanco;
    try
        if (not FDManager.IsConnectionDef('RINHA')) then
            FDManager.AddConnectionDef('RINHA', 'FB', oParams)
        else
            FDManager.ModifyConnectionDef('RINHA', oParams)
    finally
        FreeAndNil(oParams);
    end;

    FDManager.Active := True;
end;

procedure TdmServer.DataModuleCreate(Sender: TObject);
begin
    CarregarVariaveisAmbiente;

    PreparaConexaoBanco;

    try
        ExcluirRegistros;
    except
    end;

    SetObtendoLeitura(False);
    IniciarWorkers;
    IniciarHealthCk;
    IniciarScheduled;
end;

procedure TdmServer.DataModuleDestroy(Sender: TObject);
begin
    FinalizarScheduled;
    FinalizarWorkers;
    FinalizarHealthCk;
end;

destructor TdmServer.Destroy;
begin
    inherited;

    FMonitoramentoAtivo := False;
    FDSServer := nil;
end;

procedure TdmServer.DSServerPagamentosGetClass(
  DSServerClass: TDSServerClass; var PersistentClass: TPersistentClass);
begin
    PersistentClass := unsmPagamentos.TsmPagamentos;
end;

procedure ExcluirRegistros;
var
    lCon: TFDConnection;
    QyPagto: TFDQuery;
begin
    lCon := CriarConexaoFirebird;
    QyPagto := TFDQuery.Create(nil);
    try
        QyPagto.Connection := lCon;

        QyPagto.SQL.Text :=
            'delete from PAYMENTS';

        try
            lCon.StartTransaction;
            QyPagto.ExecSQL;
            lCon.Commit;
        except
            on E : Exception do
            begin
                lCon.Rollback;
                GerarLog('Erro Gravar: ' + E.Message);
            end;
        end;
    finally
        QyPagto.Free;
        DestruirConexaoFirebird(lCon);
    end;
end;

function BindPort(APort: Integer): Boolean;
var
    LTestServer: IIPTestServer;
begin
    Result := True;
    try
        LTestServer := PeerFactory.CreatePeer('', IIPTestServer) as IIPTestServer;
        LTestServer.TestOpenPort(APort, nil);
        LTestServer := nil;
    except
        on E : Exception do
        begin
            GerarLog('- Teste de porta: ' + E.Message);
            Result := False;
        end;
    end;
end;

function CheckPort(Aport: Integer): Integer;
begin
    if BindPort(Aport) then
        Result := Aport
    else
        Result := 0;
end;

procedure WriteCommands;
begin
    GerarLog(sCommands);
    GerarLog(cArrow, False);
end;

procedure StartServer(const AServer: TIdHTTPWebBrokerBridge);
begin
    if not AServer.Active then
    begin
        if CheckPort(AServer.DefaultPort) > 0 then
        begin
            GerarLog(Format(sStartingServer, [AServer.DefaultPort]));
            AServer.Bindings.Clear;
            AServer.Active := True;
        end
        else
            GerarLog(Format(sPortInUse, [AServer.DefaultPort.ToString]));
    end
    else
        GerarLog(sServerRunning);

    GerarLog('Configuração do Ambiente');
    GerarLog('==================================');
    GerarLog('(DEBUG) Debug Ativo: ' + BoolToStr(FDebug, True));
    GerarLog('(DEFAULT_URL) Url Default: ' + FUrl);
    GerarLog('(FALLBACK_URL) Url Fallback: ' + FUrlFall);
    GerarLog('(CON_TIME_OUT) Timeout Conexão: ' + IntToStr(FConTimeOut));
    GerarLog('(READ_TIME_OUT) Timeout Retorno Health: ' + IntToStr(FReadTimeOut));
    GerarLog('(RES_TIME_OUT) Timeout Padrão Processamento: ' + IntToStr(FResTimeOut));
    GerarLog('(NUM_WORKERS_FILA) Quantidade de Workers da Fila: ' + IntToStr(FNumMaxWorkersFila));
    GerarLog('(NUM_WORKERS_PROCESSO) Quantidade de Workers do Processo: ' + IntToStr(FNumMaxWorkersProcesso));
    GerarLog('(TEMPO_FILA) Tempo Descarga de Fila: ' + IntToStr(FTempoFila));

    GerarLog(cArrow);
end;

procedure TerminateThreads;
begin
    if TDSSessionManager.Instance <> nil then
        TDSSessionManager.Instance.TerminateAllSessions;
end;

procedure StopServer(const AServer: TIdHTTPWebBrokerBridge);
begin
    if AServer.Active then
    begin
        GerarLog(sStoppingServer);
        TerminateThreads;
        AServer.Active := False;
        AServer.Bindings.Clear;
        GerarLog(sServerStopped);
    end
    else
        GerarLog(sServerNotRunning);
    GerarLog(cArrow);
end;

procedure WriteStatus(const AServer: TIdHTTPWebBrokerBridge);
begin
    GerarLog(sIndyVersion + AServer.SessionList.Version);
    GerarLog(sActive + AServer.Active.ToString(TUseBoolStrs.True));
    GerarLog(sPort + AServer.DefaultPort.ToString);
    GerarLog(sSessionID + AServer.SessionIDCookieName);
    GerarLog(cArrow);
end;

procedure RunDSServer(const AServer: TIdHTTPWebBrokerBridge);
    procedure ModoConsole;
    var
        LResponse: string;
    begin
        // Modelo Console
        WriteCommands;
        while True do
        begin
            Readln(LResponse);
            LResponse := LowerCase(LResponse);
            if sametext(LResponse, cCommandStart) then
                StartServer(AServer)
            else if sametext(LResponse, cCommandStatus) then
                WriteStatus(AServer)
            else if sametext(LResponse, cCommandStop) then
                StopServer(AServer)
            else if sametext(LResponse, cCommandHelp) then
                WriteCommands
            else if sametext(LResponse, cCommandExit) then
                if AServer.Active then
                begin
                    StopServer(AServer);
                    break
                end
                else
                    break
            else
            begin
                Writeln(sInvalidCommand);
                Write(cArrow);
            end;
        end;
    end;
begin
    {$IFDEF SERVICO}
        FServerIniciado := False;
    {$ENDIF}

    {$IFNDEF LINUX64}
        FPathAplicacao := ExtractFilePath(ParamStr(0));
    {$ENDIF}

    {$IFNDEF SERVICO}
        ModoConsole;
    {$ELSE}
        // Modelo serviço
        try
            StartServer(AServer);

            FServerIniciado := True;
        except
            on E : Exception do
            begin
                GerarLog(E.Message);
            end;
        end;
    {$ENDIF}
end;

initialization
    FModule := TdmServer.Create(nil);

finalization
    FModule.Free;

end.

