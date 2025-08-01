unit unWorkerHelper;

interface

uses
    System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections;

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
      procedure Iniciar(const QtdeWorkers: Integer);
    end;

implementation

uses undmServer;

{ TWorker }

constructor TWorker.Create(const AProc: TProc);
begin
    inherited Create(False); // Inicia direto
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

    // Avisa os workers que tem coisa nova
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

procedure TFilaWorkerManager.Iniciar(const QtdeWorkers: Integer);
var
    I: Integer;
begin
    if FProcessamentoAtivo then
        Exit;

    FProcessamentoAtivo := True;

    for I := 1 to QtdeWorkers do
    begin
        FListaWorker.Add(
        TWorker.Create(
        procedure
        var
            Tarefa: TProc;
        begin
            while not TThread.CurrentThread.CheckTerminated do
            begin
                // Aguarda evento ou tarefa nova
                FEventoFila.WaitFor(INFINITE);

                if not FProcessamentoAtivo then
                    Break;

                TMonitor.Enter(FTaskQueue);
                try
                    if FTaskQueue.Count > 0 then
                        Tarefa := FTaskQueue.Dequeue()
                    else
                        Tarefa := nil;
                finally
                    TMonitor.Exit(FTaskQueue);
                end;

                if Assigned(Tarefa) then
                    Tarefa;
            end;
        end));
    end;
end;

end.
