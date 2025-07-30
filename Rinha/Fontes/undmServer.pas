unit undmServer;

interface

uses System.SysUtils, System.Classes, System.IOUtils, System.SyncObjs, System.DateUtils, System.Json,
  Datasnap.DSServer, Datasnap.DSCommonServer, Datasnap.DSAuth, Datasnap.DSSession,
  IPPeerServer, IPPeerAPI, IdHTTPWebBrokerBridge, FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.UI.Intf, FireDAC.Phys.Intf,
  FireDAC.Stan.Def, FireDAC.Phys, FireDAC.Comp.Client, FireDAC.ConsoleUI.Wait, FireDAC.Phys.FBDef, FireDAC.Phys.IBBase, FireDAC.Phys.FB, FireDAC.Comp.UI,
  IdBaseComponent, IdComponent, IdTCPConnection, IdTCPClient, IdHTTP, System.Generics.Collections;

type
  TRequisicaoPendente = record
    correlationId: string;
    amount: Double;
    requestedAt: String;

    constructor Create(const AId: string; AAmount: Double; ARequestedAt: String);
  end;

  TdmServer = class(TDataModule)
    DSServer: TDSServer;
    DSServerPagamentos: TDSServerClass;
    FDManagerRinha: TFDManager;
    FDGUIxWaitCursor1: TFDGUIxWaitCursor;
    FDPhysFBDriverLink1: TFDPhysFBDriverLink;
    IdHTTP: TIdHTTP;
    IdHTTPPagamentos: TIdHTTP;
    procedure DSServerPagamentosGetClass(DSServerClass: TDSServerClass;
      var PersistentClass: TPersistentClass);
    procedure DataModuleCreate(Sender: TObject);
  private
    FMonitoramentoAtivo: Boolean;
    FProcessamentoAtivo: Boolean;
    procedure PreparaConexaoBanco;
    procedure MonitorarServicoPagamento;
    procedure IniciarServicoPagamento;
    { Private declarations }
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

function DSServer: TDSServer;

procedure TerminateThreads;
procedure RunDSServer(const AServer: TIdHTTPWebBrokerBridge);
procedure StopServer(const AServer: TIdHTTPWebBrokerBridge);
function GetEnvURL(const EnvVar, DefaultURL: string): string;
procedure GerarLog(lsMsg : String; lbForcaArquivo : Boolean = False; lbQuebraLinhaConsole : Boolean = True);

var
    FUrl: String;
    FUrlFall: String;
    FModule: TComponent;
    FDSServer: TDSServer;
    FPathAplicacao: String;
    FLogLock: TCriticalSection;
    FMonitorLock: TCriticalSection;
    FDefaultAtivo: Boolean;
    FTempoMinimoRespota: Integer;

    FFilaEnvio: TList<TRequisicaoPendente>;
    FFilaReEnvio: TList<TRequisicaoPendente>;
    FFilaLock: TCriticalSection;


    {$IFDEF SERVICO}
        FServerIniciado: Boolean;
    {$ENDIF}

    {$IFDEF LINUX64}
        FSobrescreveDefineServico: Boolean;
        FPidFile : String;
    {$ENDIF}

implementation

{%CLASSGROUP 'System.Classes.TPersistent'}

{$R *.dfm}

uses
    unsmPagamentos, unConstantes, unDBHelper;

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

procedure TdmServer.MonitorarServicoPagamento;
begin
    FMonitoramentoAtivo := True;
    FDefaultAtivo := True;
    FTempoMinimoRespota := cTempoMinimoResposta;

    IdHTTP.ConnectTimeout := cTempoMinimoTimeOut;
    IdHTTP.ReadTimeout := 100;
    IdHTTP.Request.ContentType := 'application/json';

    TThread.CreateAnonymousThread(
    procedure
    var
        lsResposta: string;
        ljResposta: TJSONObject;
        lbFailing: Boolean;
        liMinResponseTime: Integer;
    begin
        while FMonitoramentoAtivo do
        begin
            Sleep(5000);

            if (Trim(FURL) <> '') then
            begin
                lbFailing := True;
                liMinResponseTime := cTempoMinimoResposta;
                try
                    lsResposta := IdHTTP.Get(FURL + '/payments/service-health');
                    ljResposta := TJSONObject.ParseJSONValue(lsResposta) as TJSONObject;
                    if Assigned(ljResposta) then
                    begin
                       ljResposta.TryGetValue('failing', lbFailing);
                       ljResposta.TryGetValue('minResponseTime', liMinResponseTime);

                       GerarLog('Servico Default failing: ' + BoolToStr(lbFailing) + ' - minResponseTime: ' + IntToStr(liMinResponseTime), True);

                       ljResposta.Free;
                    end;
                except
                    on E: Exception do
                    begin
                        GerarLog('Erro ao verificar ambiente: ' + E.Message, True);
                    end;
                end;

                if (liMinResponseTime < cTempoMinimoResposta) then
                    liMinResponseTime := cTempoMinimoResposta;

                FMonitorLock.Enter;
                try
                    FDefaultAtivo := not lbFailing;
                    FTempoMinimoRespota := liminResponseTime;
                finally
                    FMonitorLock.Leave;
                end;
            end;
        end;
    end).Start;
end;

procedure TdmServer.IniciarServicoPagamento;
begin
    FProcessamentoAtivo := True;

    IdHTTPPagamentos.ConnectTimeout := cTempoMinimoTimeOut;
    IdHTTPPagamentos.Request.ContentType := 'application/json';

    TThread.CreateAnonymousThread(
    procedure
        function EnviarParaProcessar(const correlationId: string; const amount: Double; const requestedAt: string; const default: Boolean): Boolean;
        var
            ljEnviar: TJSONObject;
            lsResposta: string;
            lsURL : String;
            lStream: TStringStream;
        begin
            IdHTTPPagamentos.ReadTimeout := FTempoMinimoRespota + 10;

            if (FTempoMinimoRespota > 110) then
            begin
                Result := False;
                Exit;
            end;

            lsURL := FUrl + '/payments';
            if (not default) then
                lsURL := FUrlFall + '/payments';

            ljEnviar := TJSONObject.Create;
            lStream  := nil;
            try
                try
                    // Monta o corpo JSON
                    ljEnviar.AddPair('correlationId', correlationId);
                    ljEnviar.AddPair('amount', TJSONNumber.Create(amount));
                    ljEnviar.AddPair('requestedAt', requestedAt);

                    lStream := TStringStream.Create(ljEnviar.ToString, TEncoding.UTF8);

                    // Envia a requisição POST
                    lsResposta :=
                        IdHTTPPagamentos.Post(
                            lsURL,
                            lStream
                        );

                    // Se chegou aqui sem exceção, assume sucesso
                    Result := True;
                except
                    on E: Exception do
                    begin
                        GerarLog('Pagamento: ' + lsURL + ' - ' + E.Message, True);
                        Result := False;
                    end;
                end;
            finally
                if Assigned(lStream) then
                    lStream.Free;

                ljEnviar.Free;
            end;
        end;

        function DefaultAtivo: Boolean;
        begin
            FMonitorLock.Enter;
            try

                Result := FDefaultAtivo;
            finally
                FMonitorLock.Leave;
            end;
        end;

        procedure ProcessarFila;
        var
            lFilaPendente: TList<TRequisicaoPendente>;
            lFilaReenvio: TList<TRequisicaoPendente>;
            lRequisicao: TRequisicaoPendente;
            lbResultado: Boolean;
        begin
            lFilaPendente := TList<TRequisicaoPendente>.Create;
            lFilaReenvio := TList<TRequisicaoPendente>.Create;

            try
                // Esvazia a fila de requisições global para uma fila pendentes
                FFilaLock.Enter;
                try
                    try
                        if (FFilaEnvio.Count > 0) then
                        begin
                            lFilaPendente.AddRange(FFilaEnvio);
                            FFilaEnvio.Clear;
                        end;
                    except
                        on E : Exception do
                        begin
                            GerarLog('Move Fila Normal: ' + E.Message, True);
                        end;
                    end;
                finally
                    FFilaLock.Leave;
                end;

                // Esvaiza a fila de reenvio global para reenvio local
                if (FFilaReEnvio.Count > 0) then
                begin
                    try
                        lFilaReenvio.AddRange(FFilaReEnvio);
                        FFilaReEnvio.Clear;
                    except
                        on E : Exception do
                        begin
                            GerarLog('Move Fila Reenvio: ' + E.Message, True);
                        end;
                    end;
                end;

                // Processar pendentes
                try
                    for lRequisicao in lFilaPendente do
                    begin
                        lbResultado := EnviarParaProcessar(lRequisicao.correlationId, lRequisicao.amount, lRequisicao.requestedAt, FDefaultAtivo);

                        if (lbResultado) then
                        begin
                            // Adicionar para gravar
                        end
                        else
                        begin
                            FFilaReEnvio.Add(lRequisicao);
                            Sleep(500);
                        end;
                    end;
                except
                    on E : Exception do
                    begin
                        GerarLog('Processar Fila Normal: ' + E.Message, True);
                    end;
                end;

                // Processar renvios
                try
                    for lRequisicao in lFilaReenvio do
                    begin
                        lbResultado := EnviarParaProcessar(lRequisicao.correlationId, lRequisicao.amount, lRequisicao.requestedAt, FDefaultAtivo);

                        if (lbResultado) then
                        begin
                            // Adicionar para gravar
                            // Aqui no reenvio em caso de falha poderiam existir outras lógicas como numero de tentativas
                            // forçar um estorno, etc em caso de um cenário real.
                        end
                        else
                        begin
                            FFilaReEnvio.Add(lRequisicao);
                            Sleep(500);
                        end;
                    end;
                except
                    on E : Exception do
                    begin
                        GerarLog('Processar Fila Reenvio: ' + E.Message, True);
                    end;
                end;
            finally
                lFilaPendente.Free;
                lFilaReenvio.Free;
            end;
        end;
    var
        ltUltimoProcessamento: TDateTime;
    begin
        ltUltimoProcessamento := Now;

        while FProcessamentoAtivo do
        begin
            if MilliSecondsBetween(Now, ltUltimoProcessamento) >= 500 then
            begin
                ltUltimoProcessamento := Now;
                ProcessarFila;
            end
            else
                Sleep(100); // pequena pausa para não consumir CPU
        end;
    end).Start;
end;

procedure TdmServer.DataModuleCreate(Sender: TObject);
begin
    PreparaConexaoBanco;

    MonitorarServicoPagamento;
    IniciarServicoPagamento;
end;

destructor TdmServer.Destroy;
begin
    inherited;
    FMonitoramentoAtivo := False;
    FProcessamentoAtivo := False;
    FDSServer := nil;
end;

procedure TdmServer.DSServerPagamentosGetClass(
  DSServerClass: TDSServerClass; var PersistentClass: TPersistentClass);
begin
    PersistentClass := unsmPagamentos.TsmPagamentos;
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
            GerarLog('- Teste de porta: ' + E.Message, True);
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
    GerarLog(cArrow, False, False);
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

function GetEnvURL(const EnvVar, DefaultURL: string): string;
begin
    Result := GetEnvironmentVariable(EnvVar);
    if Result = '' then
        Result := DefaultURL;
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

        FUrl := GetEnvURL('DEFAULT_URL', 'http://localhost:8001');
        FUrlFall := GetEnvURL('FALLBACK_URL', 'http://localhost:8002');
    {$ENDIF}

    {$IFNDEF LINUX64}
        FPathAplicacao := ExtractFilePath(ParamStr(0));
    {$ENDIF}

    {$IFNDEF SERVICO}
        ModoConsole;
    {$ELSE}
        // Esta condição de aplica ao linux onde não é possivel tratar as duas opções por define
        {$IFDEF LINUX64}
            if (FSobrescreveDefineServico) then
            begin
                ModoConsole;
                Exit;
            end;
        {$ENDIF}

        // Modelo serviço
        try
            StartServer(AServer);

            FServerIniciado := True;
        except
            on E : Exception do
            begin
                GerarLog(E.Message, True);
            end;
        end;
    {$ENDIF}
end;

procedure GerarLog(lsMsg : String; lbForcaArquivo : Boolean; lbQuebraLinhaConsole : Boolean);
var
    lsArquivo : String;
    lsData : String;
begin
    {$IFNDEF SERVICO}
        if (lbQuebraLinhaConsole) then
            Writeln(lsMsg)
        else
            Write(lsMsg);
    {$ELSE}
        {$IFDEF LINUX64}
            if (FSobrescreveDefineServico) then
            begin
                if (lbQuebraLinhaConsole) then
                    Writeln(lsMsg)
                else
                    Write(lsMsg);
            end;
        {$ENDIF}
    {$ENDIF}

    if (lbForcaArquivo) then
    begin
        FLogLock.Enter;
        try
            try
                if (not DirectoryExists(FPathAplicacao + 'Logs')) then
                    CreateDir(FPathAplicacao + 'Logs');

                lsData := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', TTimeZone.Local.ToUniversalTime(Now));

                lsArquivo := FPathAplicacao + 'Logs' + PathDelim + 'log' + FormatDateTime('ddmmyyyy', Date) + '.txt';

                TFile.AppendAllText(lsArquivo, lsData + ':' + lsMsg + sLineBreak, TEncoding.UTF8);

            except
            end;
         finally
            FLogLock.Leave;
         end;
    end;
end;

{ TRequisicaoPendente }

constructor TRequisicaoPendente.Create(const AId: string; AAmount: Double; ARequestedAt: String);
begin
    correlationId := AId;
    amount := AAmount;
    requestedAt := ARequestedAt;
end;

initialization
    FModule := TdmServer.Create(nil);
    FLogLock := TCriticalSection.Create;
    FMonitorLock := TCriticalSection.Create;
    FFilaLock := TCriticalSection.Create;
    FFilaEnvio := TList<TRequisicaoPendente>.Create;
    FFilaReEnvio := TList<TRequisicaoPendente>.Create;

finalization
    FModule.Free;
    FLogLock.Free;
    FMonitorLock.Free;
    FFilaLock.Free;
    FFilaEnvio.Free;
    FFilaReEnvio.Free;
end.

