unit undmServer;

interface

uses System.SysUtils, System.Classes, System.IOUtils, System.SyncObjs, System.DateUtils, System.Json,
  Datasnap.DSServer, Datasnap.DSCommonServer, Datasnap.DSAuth, Datasnap.DSSession,
  IPPeerServer, IPPeerAPI, IdHTTPWebBrokerBridge, FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.UI.Intf, FireDAC.Phys.Intf,
  FireDAC.Stan.Def, FireDAC.Phys, FireDAC.Comp.Client, FireDAC.ConsoleUI.Wait, FireDAC.Phys.FBDef, FireDAC.Phys.IBBase, FireDAC.Phys.FB, FireDAC.Comp.UI,
  IdBaseComponent, IdComponent, IdTCPConnection, IdTCPClient, IdHTTP, System.Generics.Collections, FireDAC.Stan.Param, FireDAC.DatS, FireDAC.DApt.Intf,
  FireDAC.Stan.Async, FireDAC.DApt, Data.DB, FireDAC.Comp.DataSet, unWorkerHelper;

type
  TRequisicaoPendente = record
    correlationId: string;
    amount: Double;
    requestedAt: String;
    error: Boolean;
    attempt: Integer;

    constructor Create(const AId: string; AAmount: Double; ARequestedAt: String; AAttempt: Integer);
  end;

  TdmServer = class(TDataModule)
    DSServer: TDSServer;
    DSServerPagamentos: TDSServerClass;
    FDManagerRinha: TFDManager;
    FDGUIxWaitCursor1: TFDGUIxWaitCursor;
    FDPhysFBDriverLink1: TFDPhysFBDriverLink;
    IdHTTP: TIdHTTP;
    procedure DSServerPagamentosGetClass(DSServerClass: TDSServerClass;
      var PersistentClass: TPersistentClass);
    procedure DataModuleCreate(Sender: TObject);
  private
    FMonitoramentoAtivo: Boolean;

    procedure PreparaConexaoBanco;
    procedure MonitorarServicoPagamento;

    { Private declarations }
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

function DSServer: TDSServer;

procedure AdicionarWorker(correlationId: string; amount: Double; requestedAt: string; attempt: Integer);
procedure TerminateThreads;
procedure RunDSServer(const AServer: TIdHTTPWebBrokerBridge);
procedure StopServer(const AServer: TIdHTTPWebBrokerBridge);
function GetEnv(const lsEnvVar, lsDefault: string): string;
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
    FilaManager: TFilaWorkerManager;

    FTempoMinimoRespostaPadrao : Integer;
    FDebug : Boolean;

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
    FTempoMinimoRespota := FTempoMinimoRespostaPadrao;

    IdHTTP.ConnectTimeout := cTempoMinimoTimeOut;
    IdHTTP.ReadTimeout := 5500;
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
                liMinResponseTime := FTempoMinimoRespostaPadrao;

                try
                    lsResposta := IdHTTP.Get(FURL + '/payments/service-health');
                    ljResposta := TJSONObject.ParseJSONValue(lsResposta) as TJSONObject;
                    if Assigned(ljResposta) then
                    begin
                        lbFailing := ljResposta.GetValue('failing').Value = 'true';
                        liMinResponseTime := StrToInt(ljResposta.GetValue('minResponseTime').Value);

                        GerarLog('Servico Default failing: ' + BoolToStr(lbFailing) + ' - minResponseTime: ' + IntToStr(liMinResponseTime), True);

                        ljResposta.Free;
                    end;
                except
                    on E: Exception do
                    begin
                        GerarLog('Erro ao verificar ambiente: ' + E.Message, True);
                    end;
                end;

                if (liMinResponseTime < FTempoMinimoRespostaPadrao) then
                    liMinResponseTime := FTempoMinimoRespostaPadrao;

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

procedure TdmServer.DataModuleCreate(Sender: TObject);
begin
    PreparaConexaoBanco;

    MonitorarServicoPagamento;
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

procedure ProcessarRequisicao(AReq: TRequisicaoPendente);
    function EnviarParaProcessar(lbDefaultProcessor: Boolean): Boolean;
    var
        ljEnviar: TJSONObject;
        lsResposta: string;
        lsURL : String;
        lStream: TStringStream;
        IdHTTPPagamentos: TIdHTTP;
    begin
        IdHTTPPagamentos := TIdHTTP.Create(nil);
        try
            IdHTTPPagamentos.ConnectTimeout := cTempoMinimoTimeOut;
            IdHTTPPagamentos.ReadTimeout :=  FTempoMinimoRespostaPadrao * AReq.attempt;
            IdHTTPPagamentos.Request.ContentType := 'application/json';

            lsURL := FUrl + '/payments';
            if (not lbDefaultProcessor) then
                lsURL := FUrlFall + '/payments';

            ljEnviar := TJSONObject.Create;
            lStream  := nil;
            try
                try
                    // Monta o corpo JSON
                    ljEnviar.AddPair('correlationId', AReq.correlationId);
                    ljEnviar.AddPair('amount', TJSONNumber.Create(AReq.amount));
                    ljEnviar.AddPair('requestedAt', AReq.requestedAt);

                    lStream := TStringStream.Create(ljEnviar.ToString, TEncoding.UTF8);

                    // Envia a requisição POST
                    lsResposta :=
                        IdHTTPPagamentos.Post(
                            lsURL,
                            lStream
                        );

                    Result := True;
                except
                    Result := False;

                    //on E: Exception do
                    //begin
                    //    GerarLog('Pagamento: ' + lsURL + ' - ' + E.Message, True);
                    //    Result := False;
                    //end;
                end;
            finally
                if Assigned(lStream) then
                    lStream.Free;

                ljEnviar.Free;
            end;
        finally
            IdHTTPPagamentos.Free;
        end;
    end;

    procedure Gravar(lbDefaultProcessor: Boolean);
    var
        lCon: TFDConnection;
        QyPagto: TFDQuery;
    begin
        lCon := CriarConexaoFirebird;
        QyPagto := TFDQuery.Create(nil);
        try
            QyPagto.Connection := lCon;

            lCon.StartTransaction;

            QyPagto.SQL.Text :=
                'insert into PAYMENTS (CORRELATION_ID, AMOUNT, STATUS, PROCESSOR, CREATED_AT) values (:CORRELATION_ID, :AMOUNT, :STATUS, :PROCESSOR, :CREATED_AT)';

            try
                with AReq do
                begin
                    QyPagto.ParamByName('CORRELATION_ID').AsString := correlationId;
                    QyPagto.ParamByName('AMOUNT').AsFloat := amount;

                    QyPagto.ParamByName('STATUS').AsString := 'success';
                    if (error) then
                        QyPagto.ParamByName('STATUS').AsString := 'error';

                    QyPagto.ParamByName('PROCESSOR').AsString := 'fallback';
                    if (lbDefaultProcessor) then
                        QyPagto.ParamByName('PROCESSOR').AsString := 'default';

                    QyPagto.ParamByName('CREATED_AT').AsDateTime := ISO8601ToDate(requestedAt);
                    QyPagto.ExecSQL;
                end;

                lCon.Commit;
            except
                on E : Exception do
                begin
                    lCon.Rollback;
                    GerarLog('Erro Gravar: ' + E.Message, True);
                end;
            end;
        finally
            QyPagto.Free;
            DestruirConexaoFirebird(lCon);
        end;
    end;

var
    lbResultado: Boolean;
    lbDefaultAtivo: Boolean;
begin
    //if (AReq.attempt < 10) then
    //begin
        inc(AReq.attempt);
        lbDefaultAtivo := FDefaultAtivo;

        //if (FTempoMinimoRespota > cTempoMinimoResposta) then
        //    dec(AReq.attempt)
        //else

        if (FTempoMinimoRespota <= FTempoMinimoRespostaPadrao) or (AReq.attempt > 5) then
        begin
            lbResultado := EnviarParaProcessar(lbDefaultAtivo);

            if (lbResultado) then
            begin
                Gravar(lbDefaultAtivo);
                Exit
            end;
        end;

        Sleep(FTempoMinimoRespostaPadrao * AReq.attempt);

        AdicionarWorker(AReq.correlationId, AReq.amount, AReq.requestedAt, AReq.attempt);
    //end
    //else
    //    GerarLog('ERRO GRAVAR: ' + AReq.correlationId, True);
end;

procedure AdicionarWorker(correlationId: string; amount: Double; requestedAt: string; attempt: Integer);
begin
    FilaManager.EnfileirarTarefa(
    procedure
    var
        ltReq : TRequisicaoPendente;
    begin
        ltReq := TRequisicaoPendente.Create(correlationId, amount, requestedAt, attempt);
        ProcessarRequisicao(ltReq);
    end);
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

function GetEnv(const lsEnvVar, lsDefault: string): string;
begin
    Result := GetEnvironmentVariable(lsEnvVar);
    if Result = '' then
        Result := lsDefault;
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
    if (not FDebug) then
        Exit;

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

constructor TRequisicaoPendente.Create(const AId: string; AAmount: Double; ARequestedAt: String; AAttempt: Integer);
begin
    correlationId := AId;
    amount := AAmount;
    requestedAt := ARequestedAt;
    error := False;
    attempt := AAttempt;
end;

initialization
    FModule := TdmServer.Create(nil);
    FLogLock := TCriticalSection.Create;
    FMonitorLock := TCriticalSection.Create;
    FDebug := GetEnv('DEBUG', 'N') = 'S';
    FilaManager := TFilaWorkerManager.Create;
    FilaManager.Iniciar(StrToInt(GetEnv('NUM_WORKERS', '1000')));
    FUrl := GetEnv('DEFAULT_URL', 'http://localhost:8001');
    FUrlFall := GetEnv('FALLBACK_URL', 'http://localhost:8002');
    FTempoMinimoRespostaPadrao := StrToInt(GetEnv('RES_TIME_OUT', '50'));


finalization
    FModule.Free;
    FLogLock.Free;
    FMonitorLock.Free;
    FilaManager.Free;
end.

