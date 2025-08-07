unit unSchedulerHelper;

interface

uses
    System.SysUtils, System.Classes, System.DateUtils, System.Generics.Collections, System.SyncObjs,
    System.JSON, System.IOUtils, System.Math, Data.SqlTimSt, Data.FmtBcd,
    System.Net.HttpClient,
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

    //procedure AdicionarWorker(const AReq : TRequisicaoPendente);
    procedure AdicionarWorkerProcessamento(const AReq : TRequisicaoPendente);
    procedure AdicionarWorkerReprocesso(const AReq : TRequisicaoPendente);
    procedure AdicionarWorkerBD(const AReq : TRequisicaoPendente; const ADefaultProcessor: Boolean);
    procedure ProcessarRequisicao(const AReq: TRequisicaoPendente);
    procedure Agendar(const AReq: TRequisicaoPendente);

var
    ListaDeAgendamentos: TThreadList<TScheduledTask>;
    RodarAgendamentos: TWorker;

implementation

function EnviarParaProcessar(const AReq: TRequisicaoPendente; const ADefaultProcessor: Boolean): Boolean;
var
    ljEnviar: TJSONObject;
    lsURL : String;
    lStream: TStringStream;
    lResponse: IHTTPResponse;

    lCon: TFDConnection;
    lQuery: TFDQuery;
    lReq: TRequisicaoPendente;
begin
    Result := False;

    lReq := AReq;

    lsURL := FUrl + '/payments';
    if (not ADefaultProcessor) then
        lsURL := FUrlFall + '/payments';

    lCon := CriarConexaoFirebird;
    lQuery := TFDQuery.Create(nil);

    ljEnviar := TJSONObject.Create;
    lStream  := nil;
    try
        with TWorkerRequest(TThread.CurrentThread) do
        begin
            try
                lQuery.Connection := lCon;
                lQuery.SQL.Text := 'insert into PAYMENTS (CORRELATION_ID, AMOUNT, STATUS, PROCESSOR, CREATED_AT) ' +
                                   'values (:CORRELATION_ID, :AMOUNT, :STATUS, :PROCESSOR, :CREATED_AT)';

                lReq.requestedAt := DateToISO8601(Now, True);

                //GarantirConexaoBD;

                with lReq do
                begin
                    lQuery.ParamByName('CORRELATION_ID').AsString := correlationId;
                    lQuery.ParamByName('AMOUNT').AsFMTBCD := amount;

                    if (error) then
                        lQuery.ParamByName('STATUS').AsString := 'error'
                    else
                        lQuery.ParamByName('STATUS').AsString := 'success';

                    if (ADefaultProcessor) then
                        lQuery.ParamByName('PROCESSOR').AsString := 'default'
                    else
                        lQuery.ParamByName('PROCESSOR').AsString := 'fallback';

                    lQuery.ParamByName('CREATED_AT').AsSQLTimeStamp := DateTimeToSQLTimeStamp(ISO8601ToDate(requestedAt));
                end;

                ljEnviar := TJSONObject.Create;
                ljEnviar.AddPair('correlationId', lReq.correlationId);
                ljEnviar.AddPair('amount', TJSONNumber.Create(lReq.amount));
                ljEnviar.AddPair('requestedAt', lReq.requestedAt);

                lStream := TStringStream.Create(ljEnviar.ToString, TEncoding.UTF8);

                lResponse := HTTPClient.Post(lsURL, lStream, nil);

                if (lResponse.StatusCode = 200) then
                begin
                    lCon.StartTransaction;
                    lQuery.ExecSQL;
                    lCon.Commit;

                    //AdicionarWorkerBD(lReq, ADefaultProcessor);
                    Result := True;
                end
                else
                begin
                    //if (Con.InTransaction) then
                    //    Con.Rollback;

                    GerarLog('Erro Processar: ' + IntToStr(lResponse.StatusCode));
                end;
            except
                on E: Exception do
                begin
                    if (lCon.InTransaction) then
                        lCon.Rollback;

                    GerarLog('Erro Processar: ' + E.Message);
                end;
            end;
        end;
    finally
        if Assigned(lStream) then
            lStream.Free;

        ljEnviar.Free;

        lQuery.Free;
        DestruirConexaoFirebird(lCon);
    end;
end;

procedure GravarRequisicao(const AReq: TRequisicaoPendente; const ADefaultProcessor: Boolean);
var
    lQuery: TFDQuery;
begin
    with TWorkerBD(TThread.CurrentThread) do
    begin
        lQuery := TFDQuery.Create(nil);
        try
            GarantirConexaoBD;

            lQuery.Connection := Con;
            lQuery.SQL.Text := 'insert into PAYMENTS (CORRELATION_ID, AMOUNT, STATUS, PROCESSOR, CREATED_AT) ' +
                               'values (:CORRELATION_ID, :AMOUNT, :STATUS, :PROCESSOR, :CREATED_AT)';

            with AReq do
            begin
                lQuery.ParamByName('CORRELATION_ID').AsString := correlationId;
                lQuery.ParamByName('AMOUNT').AsFMTBCD := amount;

                if (error) then
                    lQuery.ParamByName('STATUS').AsString := 'error'
                else
                    lQuery.ParamByName('STATUS').AsString := 'success';

                if (ADefaultProcessor) then
                    lQuery.ParamByName('PROCESSOR').AsString := 'default'
                else
                    lQuery.ParamByName('PROCESSOR').AsString := 'fallback';

                lQuery.ParamByName('CREATED_AT').AsSQLTimeStamp := DateTimeToSQLTimeStamp(ISO8601ToDate(requestedAt));

                Con.StartTransaction;
                try
                    lQuery.ExecSQL;
                    Con.Commit;
                    FilaLogger.LogExecucao(AReq.correlationId, sfSalvo, 0);
                except
                    on E: Exception do
                    begin
                        if Con.InTransaction then
                            Con.Rollback;

                        GerarLog('Erro Gravar: ' + E.Message);
                    end;
                end;
            end;
        finally
            lQuery.Free;
        end;
    end;
end;

procedure ProcessarRequisicao(const AReq: TRequisicaoPendente);
var
    lbDefault: Boolean;
begin
    lbDefault := True;
    if AReq.attempt > FNumTentativasDefault then
        lbDefault := ServiceHealthMonitor.GetDefaultAtivo;

    if AReq.attempt < 10 then
    begin
        if (EnviarParaProcessar(AReq, lbDefault)) then
        begin
            if (AReq.attempt <= FNumTentativasDefault) and (not ServiceHealthMonitor.GetDefaultAtivo) then
            begin
                GerarLog('Voltou Sozinho');
                ServiceHealthMonitor.SetDefaultAtivo(True);
            end;

            Exit;
        end;

        ServiceHealthMonitor.VerificarSinal;

        AdicionarWorkerReprocesso(AReq);
    end
    else
    begin
        GerarLog('Transação Perdida: ' + AReq.correlationId);
        FilaLogger.LogExecucao(AReq.correlationId, sfDescartado, 0);
    end;


    ServiceHealthMonitor.VerificarSinal;
end;

{procedure AdicionarWorker(const AReq : TRequisicaoPendente);
begin
    FilaWorkerManager.EnfileirarTarefa(
    procedure
    begin
        Agendar(AReq);
    end);
end;   }

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

procedure AdicionarWorkerBD(const AReq : TRequisicaoPendente; const ADefaultProcessor: Boolean);
begin
    FilaWorkerBD.EnfileirarTarefa(
    procedure
    begin
        GravarRequisicao(AReq, ADefaultProcessor);
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
    lLista: TList<TScheduledTask>;
    lListaProcessar: TList<TScheduledTask>;
    lListaReagendar: TList<TScheduledTask>;
    I: Integer;
begin
    lListaProcessar := TList<TScheduledTask>.Create;
    lListaReagendar := TList<TScheduledTask>.Create;
    try
        lLista := ListaDeAgendamentos.LockList;
        try
            lListaProcessar.AddRange(lLista);
            lLista.Clear;
        finally
            ListaDeAgendamentos.UnlockList;
        end;

        for I := 0 to lListaProcessar.Count - 1 do
        begin
            try
                if Now >= lListaProcessar[I].ExecuteAt then
                    AdicionarWorkerProcessamento(lListaProcessar[I].AReq)
                else
                    lListaReagendar.Add(lListaProcessar[I]);
            except
                on E: Exception do
                    GerarLog('Erro reprocessamento: ' + E.Message);
            end;
        end;

        lLista := ListaDeAgendamentos.LockList;
        try
            lLista.AddRange(lListaReagendar);
        finally
            ListaDeAgendamentos.UnlockList;
        end;
    finally
        lListaProcessar.Free;
        lListaReagendar.Free;
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

    ListaDeAgendamentos.Free;
end;

end.

