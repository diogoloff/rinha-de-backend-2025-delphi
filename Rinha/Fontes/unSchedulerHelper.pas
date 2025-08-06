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
    procedure AdicionarWorkerBD(const AReq : TRequisicaoPendente; const ADefaultProcessor: Boolean);
    procedure ProcessarRequisicao(const AReq: TRequisicaoPendente);
    procedure AgendarProcesso(const AReq: TRequisicaoPendente);

var
    ListaAgendamentos: TThreadList<TScheduledTask>;
    RodarAgendamentos: TWorker;

implementation

function EnviarParaProcessar(AReq: TRequisicaoPendente; const ADefaultProcessor: Boolean): Boolean;
var
    ljEnviar: TJSONObject;
    lsURL : String;
    lStream: TStringStream;
    //liTempoMinimoResposta: Integer;
begin
    Result := False;
    //liTempoMinimoResposta := ServiceHealthMonitor.GetTempoMinimoResposta;
    //IdHTTPPagamentos.ReadTimeout := liTempoMinimoResposta;

    lsURL := FUrl + '/payments';
    if (not ADefaultProcessor) then
        lsURL := FUrlFall + '/payments';

    ljEnviar := TJSONObject.Create;
    lStream  := nil;
    try
        with TWorkerRequest(TThread.CurrentThread) do
        begin
            try
                {GarantirConexaoBD;

                with AReq do
                begin
                    requestedAt := DateToISO8601(Now, True);

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
                end; }

                AReq.requestedAt := DateToISO8601(Now, True);
                ljEnviar.AddPair('correlationId', AReq.correlationId);
                ljEnviar.AddPair('amount', TJSONNumber.Create(AReq.amount));
                ljEnviar.AddPair('requestedAt', AReq.requestedAt);

                lStream := TStringStream.Create(ljEnviar.ToString, TEncoding.UTF8);

                // Envia a requisição POST
                IdHTTP.Post(lsURL, lStream);
                AdicionarWorkerBD(AReq, ADefaultProcessor);

                //Query.ExecSQL;
                //Con.Commit;

                FilaLogger.LogExecucao(AReq.correlationId, sfSalvo, 0);

                // Talvez fazer o bloqueio intencional se timeout estiver muito alto, mesmo que esteja validando

                Result := True;
            except
                on E: Exception do
                begin
                    //if (Con.InTransaction) then
                    //    Con.Rollback;
                    // Talvez fazer o bloqueio intencional para só voltar depois de um tempo se estiver dando muito erro

                    //GerarLog('Erro Processar: ' + E.Message);
                end;
            end;
        end;
    finally
        if Assigned(lStream) then
            lStream.Free;

        ljEnviar.Free;
    end;
end;

procedure GravarRequisicao(const AReq: TRequisicaoPendente; const ADefaultProcessor: Boolean);
begin
    with TWorkerBD(TThread.CurrentThread) do
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

                FilaLogger.LogExecucao(AReq.correlationId, sfSalvo, 0);
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

    //while GetObtendoLeitura do
    //    Sleep(1);

    lbDefault := True;
    if AReq.attempt > 5 then
        lbDefault := ServiceHealthMonitor.GetDefaultAtivo;

    //if AReq.attempt < 10 then
    //begin
        if (EnviarParaProcessar(AReq, lbDefault)) then
        begin
            {if (AReq.attempt = 1) and ((not ServiceHealthMonitor.GetDefaultAtivo) or (ServiceHealthMonitor.GetFilaCongestionada)) then
            begin
                GerarLog('Voltou Sozinho:');
                ServiceHealthMonitor.SetFilaCongestionada(False);
                ServiceHealthMonitor.SetDefaultAtivo(True);
            end; }

            if (AReq.attempt <= 5) and (not ServiceHealthMonitor.GetDefaultAtivo) then
            begin
                GerarLog('Voltou Sozinho:');
                ServiceHealthMonitor.SetDefaultAtivo(True);
            end;

            //GravarRequisicao(AReq, lbDefault);
            Exit
        end;

        //if (AReq.attempt > 5) then
        //    ServiceHealthMonitor.SetFilaCongestionada(True);

        ServiceHealthMonitor.VerificarSinal;
        AdicionarWorker(AReq);
    {end
    else
    begin
        GerarLog('Transação Perdida: ' + AReq.correlationId);
        FilaLogger.LogExecucao(AReq.correlationId, sfDescartado, 0);
    end; }
end;

procedure AdicionarWorker(const AReq : TRequisicaoPendente);
begin
    FilaWorkerManager.EnfileirarTarefa(
    procedure
    begin
        AgendarProcesso(AReq);
    end);
end;

procedure AdicionarWorkerBD(const AReq : TRequisicaoPendente; const ADefaultProcessor: Boolean);
begin
    FilaWorkerBD.EnfileirarTarefa(
    procedure
    begin
        GravarRequisicao(AReq, ADefaultProcessor);
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

procedure AgendarProcesso(const AReq: TRequisicaoPendente);
var
    lLista: TList<TScheduledTask>;
    lTask: TScheduledTask;
begin
    if (AReq.attempt = 0) then
        lTask.ExecuteAt := Now
    else
        lTask.ExecuteAt := IncMilliSecond(Now, CalcularTempoAdaptativo(AReq));

    lTask.AReq := AReq;
    Inc(lTask.AReq.attempt);

    lLista := ListaAgendamentos.LockList;
    try
        lLista.Add(lTask);
    finally
        ListaAgendamentos.UnlockList;
    end;
end;

procedure ExecutarAgendamentos(const AReprocesso: Boolean);
var
    lLista: TList<TScheduledTask>;
    I: Integer;
begin
    lLista := ListaAgendamentos.LockList;
    try
        for I := lLista.Count - 1 downto 0 do
        begin
            {if (lLista[I].AReq.attempt > 1) then
            begin
                if (ServiceHealthMonitor.GetFilaCongestionada) then
                    Continue;
            end;  }

            if Now >= lLista[I].ExecuteAt then
            begin
                AdicionarWorkerProcessamento(lLista[I].AReq);
                lLista.Delete(I);
            end;
        end;
    finally
        ListaAgendamentos.UnlockList;
    end;
end;

procedure IniciarScheduled;
begin
    ListaAgendamentos := TThreadList<TScheduledTask>.Create;

    RodarAgendamentos := TWorker.Create;
    RodarAgendamentos.SetarTarefa(
    procedure
    begin
        while not TThread.CurrentThread.CheckTerminated do
        begin
            ExecutarAgendamentos(False);
            Sleep(FTempoFila);
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

    ListaAgendamentos.Free;
end;

end.

