unit unWorkerHelper;

interface

uses
    System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections, unGenerica,
    IdBaseComponent, IdComponent, IdTCPConnection, IdTCPClient, IdHTTP;

type
    TWorker = class(TThread)
    private
        FIdHTTP: TIdHTTP;
        FExecutar: TProc;
    protected
        procedure Execute; override;
    public
        constructor Create(const AProc: TProc; ACriarHTTP: Boolean = False);
        destructor Destroy; override;
    end;

    TFilaWorkerManager = class
    private
        FTaskQueue: TQueue<TProc>;
        FEventoFila: TEvent;
        FListaWorker: TList<TWorker>;
        FProcessamentoAtivo: Boolean;
    public
        constructor Create;
        destructor Destroy; override;

        procedure EnfileirarTarefa(const ATarefa: TProc);
        procedure Finalizar;
        procedure Iniciar(const AQtdeWorkers: Integer);
        function QtdeItens: Integer;
    end;

    procedure IniciarWorkers;
    procedure FinalizarWorkers;

var
    FilaWorkerManager: TFilaWorkerManager;
    FilaWorkerProcess: TFilaWorkerManager;
    FilaWorkerSave: TFilaWorkerManager;

implementation

{ TWorker }

constructor TWorker.Create(const AProc: TProc; ACriarHTTP: Boolean = False);
begin
    inherited Create(False);
    FreeOnTerminate := False;

    if (ACriarHTTP) then
    begin
        FIdHTTP := TIdHTTP.Create(nil);
        FIdHTTP.ConnectTimeout      := FConTimeOut;
        FIdHTTP.Request.ContentType := 'application/json';
    end;
    
    FExecutar := AProc;
end;

destructor TWorker.Destroy;
begin
    if (Assigned(FIdHTTP)) then
        FIdHTTP.Free;

    inherited;
end;

procedure TWorker.Execute;
begin
    if Assigned(FExecutar) then
        FExecutar;
end;

{ TFilaWorkerManager }

constructor TFilaWorkerManager.Create;
begin
    inherited Create;

    FTaskQueue := TQueue<TProc>.Create;
    FEventoFila := TEvent.Create(nil, True, False, '');   // colocado para reset manual
    FListaWorker := TList<TWorker>.Create;
    FProcessamentoAtivo := False;
end;

destructor TFilaWorkerManager.Destroy;
begin
    Finalizar;

    FListaWorker.Free;
    FEventoFila.Free;
    FTaskQueue.Free;

    inherited;
end;

procedure TFilaWorkerManager.EnfileirarTarefa(const ATarefa: TProc);
var
    lbAcordar: Boolean;
begin
    TMonitor.Enter(FTaskQueue);
    try
        lbAcordar := FTaskQueue.Count = 0;
        FTaskQueue.Enqueue(ATarefa);
    finally
        TMonitor.Exit(FTaskQueue);
    end;

    // Avisa os workers que tem trabalho
    if lbAcordar then
        FEventoFila.SetEvent;
end;

procedure TFilaWorkerManager.Finalizar;
var
    Worker: TWorker;
begin
    FProcessamentoAtivo := False;

    // Sinaliza os workers pra que eles possam sair do wait
    FEventoFila.SetEvent;

    // Termina cada worker da forma correta
    for Worker in FListaWorker do
    begin
        Worker.Terminate;
        Worker.WaitFor;
        Worker.Free;
    end;

    FListaWorker.Clear;
end;

procedure TFilaWorkerManager.Iniciar(const AQtdeWorkers: Integer);
var
    I: Integer;
begin
    if FProcessamentoAtivo then
        Exit;

    FProcessamentoAtivo := True;

    for I := 1 to AQtdeWorkers do
    begin
        FListaWorker.Add(
        TWorker.Create(
        procedure
        var
            lTarefa: TProc;
        begin
            while not TThread.CurrentThread.CheckTerminated do
            begin
                if not FProcessamentoAtivo then
                    Break;

                if FTaskQueue.Count = 0 then
                begin
                    // Se não tem nada pra fazer, espera um pouco
                    FEventoFila.WaitFor(50);
                    Continue;
                end;

                // Aguarda evento até ser sinalizado
                //FEventoFila.WaitFor(1000);

                TMonitor.Enter(FTaskQueue);
                try
                    if FTaskQueue.Count > 0 then
                        lTarefa := FTaskQueue.Dequeue()
                    else
                        lTarefa := nil;
                finally
                    TMonitor.Exit(FTaskQueue);
                end;

                if Assigned(lTarefa) then
                begin
                    try
                        lTarefa;
                    except
                        on E: Exception do
                        begin
                            // Logar falha da tarefa aqui, se necessário
                            GerarLog(PChar('Erro: ' + E.Message));
                        end;
                    end;
                end;

                // Se a fila estiver vazia, resetamos o evento manualmente
                if FTaskQueue.Count = 0 then
                    FEventoFila.ResetEvent;
            end;
        end));
    end;
end;

function TFilaWorkerManager.QtdeItens: Integer;
begin
    TMonitor.Enter(FTaskQueue);
    try
        Result := FTaskQueue.Count;
    finally
        TMonitor.Exit(FTaskQueue);
    end;
end;

procedure IniciarWorkers;
begin
    // Fila para organização das requisições
    FilaWorkerManager := TFilaWorkerManager.Create;
    FilaWorkerManager.Iniciar(FNumMaxWorkers);

    // Fila para processamento
    FilaWorkerProcess := TFilaWorkerManager.Create;
    FilaWorkerProcess.Iniciar(FNumMaxWorkers);

    // Fila exclusiva para salvar no banco de dados, usada no normal e reprocessametno
    FilaWorkerSave := TFilaWorkerManager.Create;
    FilaWorkerSave.Iniciar(FNumMaxWorkers);     // aqui tava *2
end;

procedure FinalizarWorkers;
begin
    if (Assigned(FilaWorkerManager)) then
        FilaWorkerManager.Free;

    if (Assigned(FilaWorkerProcess)) then
        FilaWorkerProcess.Free;

    if (Assigned(FilaWorkerSave)) then
        FilaWorkerSave.Free;
end;

end.
