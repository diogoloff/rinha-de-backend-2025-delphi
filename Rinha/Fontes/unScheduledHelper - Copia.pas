unit unScheduledHelper;

interface

uses
    System.SysUtils, System.Classes, System.DateUtils, System.Generics.Collections, System.SyncObjs,
    System.JSON, System.IOUtils, System.Math,

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

    procedure AdicionarWorker(const AReq : TRequisicaoPendente);
    procedure AdicionarWorkerReprocesso(const AReq : TRequisicaoPendente);
    procedure AdicionarWorkerGravacao(const AReq : TRequisicaoPendente; const ADefault: Boolean);
    procedure ProcessarRequisicao(const AReq: TRequisicaoPendente);
    procedure Agendar(const AReq: TRequisicaoPendente);
    procedure AgendarReprocessamento(const AReq: TRequisicaoPendente);
    procedure LiberaCarga;

var
    ListaDeAgendamentos: TThreadList<TScheduledTask>;
    ListaDeReAgendamentos: TThreadList<TScheduledTask>;
    RodarAgendamentos: TWorker;
    RodarReAgendamentos: TWorker;

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

function GetCargaTotalFilas: Integer;
begin
    try
        Result := ListaDeAgendamentos.LockList.Count + ListaDeReAgendamentos.LockList.Count;
    finally
        ListaDeAgendamentos.UnlockList;
        ListaDeReAgendamentos.UnlockList;
    end;
end;

procedure LiberaCarga;
var
    Carga: Integer;
begin
    try
        Carga := GetCargaTotalFilas;

        if Carga >= FNumMaxRetain then
        begin
            GerarLog(Format('Carga excessiva (%d itens): aguardando...', [Carga]));
            Sleep(5 + (Carga div 10)); // atraso proporcional à carga
        end;
    except
        on E : Exception do
        begin
            GerarLog(E.Message);
        end;
    end;
end;

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
                begin
                    GerarLog('Timeout: ' + IntToStr(TempoTotalMs));
                    ServiceHealthMonitor.SetFilaCongestionada(True);
                end
                else
                    ServiceHealthMonitor.SetFilaCongestionada(False);

                GerarLog('Tentativa: ' + IntToStr(AReq.attempt) + ' - Efetuada: ' +  AReq.correlationId);

                Result := True;
            except
                on E: EIdHTTPProtocolException do
                begin
                    TempoTotalMs := TThread.GetTickCount - StartTick;
                    FilaLogger.LogExecucao(AReq.correlationId, sfErro500, TempoTotalMs);

                    ServiceHealthMonitor.SetFilaCongestionada(True);
                end;

                on E: Exception do
                begin
                    TempoTotalMs := TThread.GetTickCount - StartTick;
                    if (E.ClassName = 'EIdReadTimeout') then
                        FilaLogger.LogExecucao(AReq.correlationId, sfTimeout, TempoTotalMs)
                    else
                        FilaLogger.LogExecucao(AReq.correlationId, sfErroDesconhecido, TempoTotalMs);

                    GerarLog('EIdReadTimeout: ' + IntToStr(TempoTotalMs));
                    ServiceHealthMonitor.SetFilaCongestionada(True);
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

procedure ProcessarRequisicao(const AReq: TRequisicaoPendente);
var
    lbDefault: Boolean;
begin
    lbDefault := True;
    if AReq.attempt > 1 then
        lbDefault := ServiceHealthMonitor.GetDefaultAtivo;

    if AReq.attempt < 10 then
    begin
        {if ServiceHealthMonitor.GetFilaCongestionada then
        begin
            if (ServiceHealthMonitor.DeveSairDaContencao) then
                ServiceHealthMonitor.SetFilaCongestionada(False)
            else
            begin
                AdicionarWorkerReprocesso(AReq);

                Exit;
            end;
        end;  }

        if (EnviarParaProcessar(AReq, lbDefault)) then
        begin
            AdicionarWorkerGravacao(AReq, lbDefault);
            Exit
        end;

        AdicionarWorkerReprocesso(AReq);
    end
    else
    begin
        GerarLog('Transação Perdida: ' + AReq.correlationId);
        FilaLogger.LogExecucao(AReq.correlationId, sfDescartado, 0);
    end;
end;

procedure AdicionarWorker(const AReq : TRequisicaoPendente);
begin
    // Tirei a questão de jogar para a fila e fazer diretamente com worker
    // Ter fila somente para as segundas tentativas
    FilaWorkerManager.EnfileirarTarefa(
    procedure
    begin
        ProcessarRequisicao(AReq);
        //Agendar(AReq);
    end);
end;

procedure AdicionarWorkerReprocesso(const AReq : TRequisicaoPendente);
begin
    FilaWorkerManager.EnfileirarTarefa(
    procedure
    begin
        AgendarReprocessamento(AReq);
    end);
end;

procedure AdicionarWorkerProcessamento(const AReq : TRequisicaoPendente);
begin
    FilaWorkerProcess.EnfileirarTarefa(
    procedure
    begin
        ProcessarRequisicao(AReq);
    end);
end;

procedure AdicionarWorkerGravacao(const AReq : TRequisicaoPendente; const ADefault: Boolean);
begin
    FilaWorkerSave.EnfileirarTarefa(
    procedure
    begin
        GravarRequisicao(AReq, ADefault);
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
    lTask.ExecuteAt := Now;
    lTask.AReq := AReq;
    Inc(lTask.AReq.attempt);

    lLista := ListaDeAgendamentos.LockList;
    try
        lLista.Add(lTask);
    finally
        ListaDeAgendamentos.UnlockList;
    end;
end;

procedure AgendarReprocessamento(const AReq: TRequisicaoPendente);
var
    lLista: TList<TScheduledTask>;
    lTask: TScheduledTask;
begin
    FilaLogger.LogEntrada(AReq.correlationId);
    lTask.ExecuteAt := IncSecond(Now, CalcularTempoAdaptativo(AReq));
    lTask.AReq := AReq;
    Inc(lTask.AReq.attempt);

    lLista := ListaDeReAgendamentos.LockList;
    try
        lLista.Add(lTask);
    finally
        ListaDeReAgendamentos.UnlockList;
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

procedure ExecutarReAgendamentos;
var
    Lista: TList<TScheduledTask>;
    I: Integer;
begin
    Lista := ListaDeReAgendamentos.LockList;
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
        ListaDeReAgendamentos.UnlockList;
    end;
end;

procedure IniciarScheduled;
begin
    ListaDeAgendamentos := TThreadList<TScheduledTask>.Create;
    ListaDeReAgendamentos := TThreadList<TScheduledTask>.Create;

    RodarAgendamentos := TWorker.Create(
    procedure
    begin
        while not TThread.CurrentThread.CheckTerminated do
        begin
            ExecutarAgendamentos;
            Sleep(500);
        end;
    end);

    RodarReAgendamentos := TWorker.Create(
    procedure
    begin
        while not TThread.CurrentThread.CheckTerminated do
        begin
            ExecutarReAgendamentos;
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

    if Assigned(RodarReAgendamentos) then
    begin
        RodarReAgendamentos.Terminate;
        RodarReAgendamentos.WaitFor;
        RodarReAgendamentos.Free;
    end;

    ListaDeReAgendamentos.Free;
end;

end.

