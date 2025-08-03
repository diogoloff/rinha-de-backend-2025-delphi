unit unScheduledHelper;

interface

uses
    System.SysUtils, System.Classes, System.DateUtils, System.Generics.Collections, System.SyncObjs,
    System.JSON, System.IOUtils,

    IdBaseComponent, IdComponent, IdTCPConnection, IdTCPClient, IdHTTP,

    FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.UI.Intf, FireDAC.Phys.Intf, FireDAC.Stan.Def,
    FireDAC.Stan.Pool, FireDAC.Stan.Async, FireDAC.Phys, FireDAC.ConsoleUI.Wait, Data.DB, FireDAC.Comp.Client,
    FireDAC.Stan.Param, FireDAC.DatS, FireDAC.DApt.Intf, FireDAC.DApt, FireDAC.Comp.DataSet,

    unGenerica, unRequisicaoPendente, unHealthHelper, unLogHelper, unDBHelper, unWorkerHelper;

type
    TScheduledTask = record
        ExecuteAt: TDateTime;
        AReq: TRequisicaoPendente;
    end;

    TScheduler = class
    private
        FTasks: TList<TScheduledTask>;
    public
        constructor Create;
        destructor Destroy; override;

        //procedure Agendar(const AReq: TRequisicaoPendente; const ASegundos: Integer);
        //procedure ExecutarTarefasPendentes;
    end;

    procedure IniciarScheduled;
    procedure FinalizarScheduled;

    procedure AdicionarWorker(const AReq : TRequisicaoPendente; const AFilaAtrasados: Boolean = False);
    procedure AdicionarWorkerGravacao(const AReq : TRequisicaoPendente; const ADefault: Boolean);
    procedure ProcessarRequisicao(const AReq: TRequisicaoPendente; const ADefaultAtivo: Boolean);
    procedure AgendarReprocessamento(const AReq: TRequisicaoPendente; const ASegundos: Integer);

var
    ListaDeAgendamentos: TThreadList<TScheduledTask>;
    AgendadorWorker: TWorker;

implementation

{ TScheduler }

constructor TScheduler.Create;
begin
    FTasks := TList<TScheduledTask>.Create;
end;

destructor TScheduler.Destroy;
begin
    FTasks.Free;
    inherited;
end;

{procedure TScheduler.Agendar(const AReq: TRequisicaoPendente; const ASegundos: Integer);
var
    Task: TScheduledTask;
begin
    Task.ExecuteAt := IncSecond(Now, ASegundos);
    Task.AReq := AReq;
    FTasks.Add(Task);
end;

procedure TScheduler.ExecutarTarefasPendentes;
var
    I: Integer;
    Task: TScheduledTask;
begin
    for I := FTasks.Count - 1 downto 0 do
    begin
        Task := FTasks[I];
        if Now >= Task.ExecuteAt then
        begin
            // Aqui você chama o processamento do AReq
            ProcessarRequisicao(Task.AReq, True);

            // Remover da lista após executar
            FTasks.Delete(I);
        end;
    end;
end; }

function EnviarParaProcessar(const AReq: TRequisicaoPendente; const lbDefaultProcessor: Boolean): Boolean;
var
    ljEnviar: TJSONObject;
    lsResposta: string;
    lsURL : String;
    lStream: TStringStream;
    IdHTTPPagamentos: TIdHTTP;
    liTempoMinimoResposta: Integer;

    StartTick: Integer;
    TempoTotalMs: Integer;
begin
    Result := False;
    liTempoMinimoResposta := ServiceHealthMonitor.GetTempoMinimoResposta;

    IdHTTPPagamentos := TIdHTTP.Create(nil);
    try
        IdHTTPPagamentos.ConnectTimeout := FConTimeOut;
        IdHTTPPagamentos.ReadTimeout := liTempoMinimoResposta;
        IdHTTPPagamentos.Request.ContentType := 'application/json';

        lsURL := FUrl + '/payments';
        if (not lbDefaultProcessor) then
            lsURL := FUrlFall + '/payments';

        ljEnviar := TJSONObject.Create;
        lStream  := nil;
        StartTick := TThread.GetTickCount;
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
                TempoTotalMs := TThread.GetTickCount - StartTick;

                FilaLogger.LogExecucao(AReq.correlationId, sfSucesso, TempoTotalMs);

                // Sinaliza alta latencia
                if (TempoTotalMs > ServiceHealthMonitor.GetTempoMaximoRespostaPadrao) then
                    ServiceHealthMonitor.SetFilaCongestionada(True);
                //else
                //    ServiceHealthMonitor.SetFilaCongestionada(False);

                Result := True;
            except
                on E: EIdHTTPProtocolException do
                begin
                    TempoTotalMs := TThread.GetTickCount - StartTick;
                    FilaLogger.LogExecucao(AReq.correlationId, sfErro500, TempoTotalMs);

                    //ServiceHealthMonitor.SetFilaCongestionada(True);
                end;

                on E: Exception do
                begin
                    TempoTotalMs := TThread.GetTickCount - StartTick;
                    if (E.ClassName = 'EIdReadTimeout') then
                        FilaLogger.LogExecucao(AReq.correlationId, sfErro500, TempoTotalMs)
                    else
                        FilaLogger.LogExecucao(AReq.correlationId, sfErroDesconhecido, TempoTotalMs);

                    //ServiceHealthMonitor.SetFilaCongestionada(True);
                end;
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

procedure GravarRequisicao(const AReq: TRequisicaoPendente; const ADefaultProcessor: Boolean);
var
    lCon: TFDConnection;
    QyPagto: TFDQuery;
begin
    lCon := CriarConexaoFirebird;
    QyPagto := TFDQuery.Create(nil);
    try
        QyPagto.Connection := lCon;

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
                if (ADefaultProcessor) then
                    QyPagto.ParamByName('PROCESSOR').AsString := 'default';

                QyPagto.ParamByName('CREATED_AT').AsDateTime := ISO8601ToDate(requestedAt);
                QyPagto.ExecSQL;
            end;
        except
            on E : Exception do
            begin
                GerarLog('Erro Gravar: ' + E.Message);
            end;
        end;
    finally
        QyPagto.Free;
        DestruirConexaoFirebird(lCon);
    end;
end;

procedure ProcessarRequisicao(const AReq: TRequisicaoPendente; const ADefaultAtivo: Boolean);
begin
    // como o incremento esta acontecendo em agendarreprocessamento, a maioria nem logou como descarte, porque
    // por algum motivo o sistema ficou com fila congestionada e não saiu mais disto

    if SecondsBetween(Now, AReq.createAt) > 20 then
        GerarLog('Requisição muito antiga, possível lag: ' + AReq.correlationId);

    if AReq.attempt < 10 then
    begin
        if ServiceHealthMonitor.GetFilaCongestionada then
        begin
            if (ServiceHealthMonitor.DeveSairDaContencao) then
                ServiceHealthMonitor.SetFilaCongestionada(False)
            else
            begin
                // 5 segundos no reagendamento talvez seja muito tempo
                // talvez trablahar com um tempo escalonado
                AgendarReprocessamento(AReq, 5);
                Exit;
            end;
        end;

        if (EnviarParaProcessar(AReq, ADefaultAtivo)) then
        begin
            AdicionarWorkerGravacao(AReq, ADefaultAtivo);
            Exit
        end;

        //AdicionarWorker(AReq, True);

        // 5 segundos no reagendamento talvez seja muito tempo
        // talvez trablahar com um tempo escalonado
        AgendarReprocessamento(AReq, 5);
    end
    else
    begin
        GerarLog('Transação Perdida: ' + AReq.correlationId);
        FilaLogger.LogExecucao(AReq.correlationId, sfDescartado, 0);
    end;
end;

{procedure ReprocessarRequisicao(AReq: TRequisicaoPendente);
var
    lbDefault : Boolean;
begin
    if SecondsBetween(Now, AReq.createAt) > 20 then
        GerarLog('Requisição muito antiga, possível lag: ' + AReq.correlationId);

    if (AReq.attempt < 10) then
    begin
        FilaLogger.LogEntrada(AReq.correlationId);

        Sleep(5000);
        inc(AReq.attempt);
        ServiceHealthMonitor.VerificarSinal;
        lbDefault := ServiceHealthMonitor.GetDefaultAtivo;

        FilaWorkerReprocess.EnfileirarTarefa(
        procedure
        begin
            ProcessarRequisicao(AReq, lbDefault);
        end);
    end
    else
    begin
        GerarLog('Transação Perdida: ' + AReq.correlationId);
        FilaLogger.LogExecucao(AReq.correlationId, sfDescartado, 0);
    end;
end; }

procedure AdicionarWorker(const AReq : TRequisicaoPendente; const AFilaAtrasados: Boolean);
begin
    if (AFilaAtrasados) then
    begin
        {FilaWorkerLater.EnfileirarTarefa(
        procedure
        begin
            ReprocessarRequisicao(AReq);
        end); }
    end
    else
    begin
        FilaWorkerManager.EnfileirarTarefa(
        procedure
        begin
            ProcessarRequisicao(AReq, True);
        end);
    end;
end;

procedure AdicionarWorkerGravacao(const AReq : TRequisicaoPendente; const ADefault: Boolean);
begin
    FilaWorkerSave.EnfileirarTarefa(
    procedure
    begin
        GravarRequisicao(AReq, ADefault);
    end);
end;

procedure AgendarReprocessamento(const AReq: TRequisicaoPendente; const ASegundos: Integer);
var
    lTask: TScheduledTask;
    lLista: TList<TScheduledTask>;
begin
    FilaLogger.LogEntrada(AReq.correlationId);

    lTask.ExecuteAt := IncSecond(Now, ASegundos);
    lTask.AReq := AReq;
    Inc(lTask.AReq.attempt);

    lLista := ListaDeAgendamentos.LockList;
    try
        lLista.Add(lTask);
    finally
        ListaDeAgendamentos.UnlockList;
    end;
end;

procedure ExecutarAgendamentos;
var
    Lista: TList<TScheduledTask>;
    I: Integer;
begin
    Lista := ListaDeAgendamentos.LockList;
    try
        for I := Lista.Count - 1 downto 0 do
        begin
            if Now >= Lista[I].ExecuteAt then
            begin
                ServiceHealthMonitor.VerificarSinal;
                ProcessarRequisicao(Lista[I].AReq, ServiceHealthMonitor.GetDefaultAtivo);
                Lista.Delete(I);
            end;
        end;
    finally
        ListaDeAgendamentos.UnlockList;
    end;
end;

procedure IniciarScheduled;
begin
    ListaDeAgendamentos := TThreadList<TScheduledTask>.Create;

    AgendadorWorker := TWorker.Create(
    procedure
    begin
        while not TThread.CurrentThread.CheckTerminated do
        begin
            ExecutarAgendamentos;
            Sleep(500);
        end;
    end);
end;

procedure FinalizarScheduled;
begin
    if Assigned(AgendadorWorker) then
    begin
        AgendadorWorker.Terminate;
        AgendadorWorker.WaitFor;
        AgendadorWorker.Free;
    end;

    ListaDeAgendamentos.Free;
end;

end.

