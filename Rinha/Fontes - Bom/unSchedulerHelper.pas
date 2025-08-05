unit unSchedulerHelper;

interface

uses
    System.SysUtils, System.Classes, System.DateUtils, System.Generics.Collections, System.SyncObjs,
    System.JSON, System.IOUtils, System.Math, Data.SqlTimSt, Data.FmtBcd,

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

    procedure IniciarScheduled;
    procedure FinalizarScheduled;

    procedure AdicionarWorker(const AReq : TRequisicaoPendente);
    procedure AdicionarWorkerProcessamento(const AReq : TRequisicaoPendente);
    procedure AdicionarWorkerReprocesso(const AReq : TRequisicaoPendente);
    procedure ProcessarRequisicao(const AReq: TRequisicaoPendente);
    procedure Agendar(const AReq: TRequisicaoPendente);

var
    ListaDeAgendamentos: TThreadList<TScheduledTask>;
    RodarAgendamentos: TWorker;

implementation

function EnviarParaProcessar(const AReq: TRequisicaoPendente; const lbDefaultProcessor: Boolean): Boolean;
var
    ljEnviar: TJSONObject;
    lsResposta: string;
    lsURL : String;
    lStream: TStringStream;
    liTempoMinimoResposta: Integer;
begin
    Result := False;
    //liTempoMinimoResposta := ServiceHealthMonitor.GetTempoMinimoResposta;
    //IdHTTPPagamentos.ReadTimeout := liTempoMinimoResposta;

    lsURL := FUrl + '/payments';
    if (not lbDefaultProcessor) then
        lsURL := FUrlFall + '/payments';

    with TWorkerRequest(TThread.CurrentThread) do
    begin
        try
            GarantirConexaoBD;

            with AReq do
            begin
                Query.ParamByName('CORRELATION_ID').AsString := correlationId;
                Query.ParamByName('AMOUNT').AsFMTBCD := amount;

                if (error) then
                    Query.ParamByName('STATUS').AsString := 'error'
                else
                    Query.ParamByName('STATUS').AsString := 'success';

                if (lbDefaultProcessor) then
                    Query.ParamByName('PROCESSOR').AsString := 'default'
                else
                    Query.ParamByName('PROCESSOR').AsString := 'fallback';

                Query.ParamByName('CREATED_AT').AsSQLTimeStamp := DateTimeToSQLTimeStamp(ISO8601ToDate(requestedAt));

                if not Query.Prepared then
                    Query.Prepare;
            end;
        except
            on E : Exception do
            begin
                GerarLog('Erro ao Preparar o Banco: ' + E.Message);
                Exit;
            end;
        end;

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
                lsResposta := IdHTTP.Post(lsURL, lStream);

                Query.ExecSQL;
                Con.Commit;
                Result := True;
            except
                on E: Exception do
                begin
                    if (Con.InTransaction) then
                        Con.Rollback;

                    GerarLog('Erro Processar: ' + E.Message);
                end;
            end;
        finally
            if Assigned(lStream) then
                lStream.Free;

            ljEnviar.Free;
        end;
    end;
end;

procedure GravarRequisicao(const AReq: TRequisicaoPendente; const ADefaultProcessor: Boolean);
begin
    with TWorkerRequest(TThread.CurrentThread) do
    begin
        try
            GarantirConexaoBD;

            with AReq do
            begin
                Query.ParamByName('CORRELATION_ID').AsString := correlationId;
                Query.ParamByName('AMOUNT').AsFMTBCD := amount;

                if (error) then
                    Query.ParamByName('STATUS').AsString := 'error'
                else
                    Query.ParamByName('STATUS').AsString := 'success';

                if (ADefaultProcessor) then
                    Query.ParamByName('PROCESSOR').AsString := 'default'
                else
                    Query.ParamByName('PROCESSOR').AsString := 'fallback';

                Query.ParamByName('CREATED_AT').AsSQLTimeStamp := DateTimeToSQLTimeStamp(ISO8601ToDate(requestedAt));

                if not Query.Prepared then
                    Query.Prepare;

                Query.ExecSQL;
                Con.Commit;
            end;
        except
            on E : Exception do
            begin
                if (Con.InTransaction) then
                    Con.Rollback;

                GerarLog('Erro Gravar: ' + E.Message);
            end;
        end;
    end;
end;

procedure ProcessarRequisicao(const AReq: TRequisicaoPendente);
var
    lbDefault: Boolean;
begin
    if not (TThread.CurrentThread is TWorkerRequest) then
        raise Exception.Create('Thread atual não é um WorkerRequest');

    lbDefault := True;
    if AReq.attempt > 1 then
        lbDefault := ServiceHealthMonitor.GetDefaultAtivo;

    if AReq.attempt < 10 then
    begin
        if (EnviarParaProcessar(AReq, lbDefault)) then
            Exit

        //AdicionarWorkerReprocesso(AReq);
    end
    else
    begin
        GerarLog('Transação Perdida: ' + AReq.correlationId);
        FilaLogger.LogExecucao(AReq.correlationId, sfDescartado, 0);
    end;
end;

procedure AdicionarWorker(const AReq : TRequisicaoPendente);
begin
    FilaWorkerManager.EnfileirarTarefa(
    procedure
    begin
        Agendar(AReq);
    end);
end;

procedure AdicionarWorkerReprocesso(const AReq : TRequisicaoPendente);
begin
    FilaWorkerManager.EnfileirarTarefa(
    procedure
    begin
        Agendar(AReq);
    end);
end;

procedure AdicionarWorkerProcessamento(const AReq : TRequisicaoPendente);
begin
    FilaWorkerRequest.EnfileirarTarefa(
    procedure
    begin
        ProcessarRequisicao(AReq);
    end);
end;

function CalcularTempoAdaptativo(const AReq: TRequisicaoPendente): Integer;
begin
    // Tempo base ajustável conforme numero de tentativas
    if (AReq.attempt <= 5) then
        Result := 1
    else
        Result := 4 + Trunc(Power(AReq.attempt - 5, 1.5));
end;

procedure Agendar(const AReq: TRequisicaoPendente);
var
    lLista: TList<TScheduledTask>;
    lTask: TScheduledTask;
begin
    FilaLogger.LogEntrada(AReq.correlationId);

    if (AReq.attempt = 0) then
        lTask.ExecuteAt := Now
    else
        lTask.ExecuteAt := IncSecond(Now, CalcularTempoAdaptativo(AReq));

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
                AdicionarWorkerProcessamento(Lista[I].AReq);
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

    RodarAgendamentos := TWorker.Create;
    RodarAgendamentos.SetarTarefa(
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
    if Assigned(RodarAgendamentos) then
    begin
        RodarAgendamentos.Terminate;
        RodarAgendamentos.WaitFor;
        RodarAgendamentos.Free;
    end;

    ListaDeAgendamentos.Free;
end;

end.

