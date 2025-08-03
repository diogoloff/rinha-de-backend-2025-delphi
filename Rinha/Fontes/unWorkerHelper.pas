unit unWorkerHelper;

interface

uses
    System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections, unGenerica;

type
    TWorker = class(TThread)
    private
        FExecutar: TProc;
    protected
        procedure Execute; override;
    public
        constructor Create(const AProc: TProc);
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
    //FilaWorkerLater: TFilaWorkerManager;
    //FilaWorkerReprocess: TFilaWorkerManager;
    FilaWorkerSave: TFilaWorkerManager;

implementation

{ TWorker }

constructor TWorker.Create(const AProc: TProc);
begin
    inherited Create(False);
    FreeOnTerminate := False;
    FExecutar := AProc;
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
    FEventoFila := TEvent.Create(nil, False, False, '');
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
begin
    TMonitor.Enter(FTaskQueue);
    try
        FTaskQueue.Enqueue(ATarefa);
    finally
        TMonitor.Exit(FTaskQueue);
    end;

    // Avisa os workers que tem trabalho
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
                // Aguarda evento até ser sinalizado
                FEventoFila.WaitFor(1000);

                if not FProcessamentoAtivo then
                    Break;

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
                    lTarefa;
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
    // Fila normal
    FilaWorkerManager := TFilaWorkerManager.Create;
    FilaWorkerManager.Iniciar(FNumMaxWorkers);

    // Fila para delay de reprocessamento, aqui gera um atraso
    //FilaWorkerLater := TFilaWorkerManager.Create;
    //FilaWorkerLater.Iniciar(FNumMaxWorkers);

    // Fila para reprocessamento
    //FilaWorkerReprocess := TFilaWorkerManager.Create;
    //FilaWorkerReprocess.Iniciar(FNumMaxWorkers);

    // Fila exclusiva para salvar no banco de dados, usada no normal e reprocessametno
    FilaWorkerSave := TFilaWorkerManager.Create;
    FilaWorkerSave.Iniciar(FNumMaxWorkers);     // aqui tava *2
end;

procedure FinalizarWorkers;
begin
    if (Assigned(FilaWorkerManager)) then
        FilaWorkerManager.Free;

    //if (Assigned(FilaWorkerLater)) then
    //    FilaWorkerLater.Free;

    //if (Assigned(FilaWorkerReprocess)) then
    //    FilaWorkerReprocess.Free;

    if (Assigned(FilaWorkerSave)) then
        FilaWorkerSave.Free;
end;

end.
