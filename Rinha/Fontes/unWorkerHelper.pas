unit unWorkerHelper;

interface

uses
    System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections, System.DateUtils,
    IdBaseComponent, IdComponent, IdTCPConnection, IdTCPClient, IdHTTP,

    FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.UI.Intf, FireDAC.Phys.Intf, FireDAC.Stan.Def,
    FireDAC.Stan.Pool, FireDAC.Stan.Async, FireDAC.Phys, FireDAC.ConsoleUI.Wait, Data.DB, FireDAC.Comp.Client,
    FireDAC.Stan.Param, FireDAC.DatS, FireDAC.DApt.Intf, FireDAC.DApt, FireDAC.Comp.DataSet,

    unGenerica, unDBHelper;

type
    TWorkerBase = class(TThread)
    protected
        FExecutar: TProc;
        FTaskQueue: TQueue<TProc>;
        FEventoFila: TEvent;
        FProcessamentoAtivo: Boolean;

        procedure Execute; override;
    public
        constructor Create;
        destructor Destroy; override;

        procedure EnfileirarTarefa(const ATarefa: TProc);
        procedure Finalizar;
        procedure SetarTarefa(const AProc: TProc);
        function QtdeItens: Integer;
    end;

    TWorker = class(TWorkerBase)
    public
        constructor Create;
    end;

    TWorkerRequest = class(TWorkerBase)
    private
        FIdHTTP: TIdHTTP;
        //FCon: TFDConnection;
        //FQuery: TFDQuery;
        //FUltimoUsoBD: TDateTime;
    public
        constructor Create;
        destructor Destroy; override;
        //procedure GarantirConexaoBD;
        //procedure VerificarExpiracaoConexaoBD;

        property IdHTTP: TIdHTTP read FIdHTTP;
        //property Con: TFDConnection read FCon;
        //property Query: TFDQuery read FQuery;
    end;

    TWorkerBD = class(TWorkerBase)
    private
        FCon: TFDConnection;
        FQuery: TFDQuery;
        FUltimoUsoBD: TDateTime;
    public
        constructor Create;
        destructor Destroy; override;
        procedure GarantirConexaoBD;
        procedure VerificarExpiracaoConexaoBD;

        property Con: TFDConnection read FCon;
        property Query: TFDQuery read FQuery;
    end;

    TFilaWorkerManager = class
    private
        FListaWorker: TList<TWorker>;
        FProcessamentoAtivo: Boolean;
    public
        constructor Create;
        destructor Destroy; override;

        procedure Iniciar(const AQtdeWorkers: Integer);
        procedure Finalizar;
        procedure EnfileirarTarefa(const ATarefa: TProc);
        function QtdeItens: Integer;
    end;

    TFilaWorkerRequest = class
    private
        FListaWorker: TList<TWorkerRequest>;
        FProcessamentoAtivo: Boolean;
    public
        constructor Create;
        destructor Destroy; override;

        procedure Iniciar(const AQtdeWorkers: Integer);
        procedure Finalizar;
        procedure EnfileirarTarefa(const ATarefa: TProc);
        function QtdeItens: Integer;
    end;

    TFilaWorkerBD = class
    private
        FListaWorker: TList<TWorkerBD>;
        FProcessamentoAtivo: Boolean;
    public
        constructor Create;
        destructor Destroy; override;

        procedure Iniciar(const AQtdeWorkers: Integer);
        procedure Finalizar;
        procedure EnfileirarTarefa(const ATarefa: TProc);
        function QtdeItens: Integer;
    end;

    procedure IniciarWorkers;
    procedure FinalizarWorkers;

var
    FilaWorkerManager : TFilaWorkerManager;
    FilaWorkerRequest : TFilaWorkerRequest;
    FilaWorkerBD : TFilaWorkerBD;

implementation

procedure IniciarWorkers;
begin
    FilaWorkerManager := TFilaWorkerManager.Create;
    FilaWorkerManager.Iniciar(FNumMaxWorkersFila);

    FilaWorkerRequest := TFilaWorkerRequest.Create;
    FilaWorkerRequest.Iniciar(FNumMaxWorkersProcesso);

    FilaWorkerBD := TFilaWorkerBD.Create;
    FilaWorkerBD.Iniciar(FNumMaxWorkersProcesso);
end;

procedure FinalizarWorkers;
begin
    if (Assigned(FilaWorkerManager)) then
        FilaWorkerManager.Free;

    if (Assigned(FilaWorkerRequest)) then
        FilaWorkerRequest.Free;

    if (Assigned(FilaWorkerBD)) then
        FilaWorkerBD.Free;
end;

{ TWorkerBase }

constructor TWorkerBase.Create;
begin
    inherited Create(False);
    FreeOnTerminate := False;

    FTaskQueue := TQueue<TProc>.Create;
    FEventoFila := TEvent.Create(nil, True, False, '');
    FProcessamentoAtivo := True;
end;

destructor TWorkerBase.Destroy;
begin
    Finalizar;
    FEventoFila.Free;
    FTaskQueue.Free;
    inherited;
end;

procedure TWorkerBase.EnfileirarTarefa(const ATarefa: TProc);
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

    if lbAcordar then
        FEventoFila.SetEvent;
end;

procedure TWorkerBase.Execute;
var
    lTarefa: TProc;
begin
    while not Terminated do
    begin
        if not FProcessamentoAtivo then
            Break;

        if FTaskQueue.Count = 0 then
        begin
            FEventoFila.WaitFor(50);

            if Self is TWorkerBD then
                TWorkerBD(Self).VerificarExpiracaoConexaoBD;

            Continue;
        end;

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
                    GerarLog(PChar('Erro: ' + E.Message));
            end;
        end;

        if FTaskQueue.Count = 0 then
            FEventoFila.ResetEvent;
    end;
end;

procedure TWorkerBase.Finalizar;
begin
    FProcessamentoAtivo := False;
    FEventoFila.SetEvent;
    Terminate;
    WaitFor;
end;

function TWorkerBase.QtdeItens: Integer;
begin
    TMonitor.Enter(FTaskQueue);
    try
        Result := FTaskQueue.Count;
    finally
        TMonitor.Exit(FTaskQueue);
    end;
end;

procedure TWorkerBase.SetarTarefa(const AProc: TProc);
begin
    FExecutar := AProc;
    EnfileirarTarefa(FExecutar);
end;

{ TWorker }

constructor TWorker.Create;
begin
    inherited Create;
end;

{ TWorkerRequest }

constructor TWorkerRequest.Create;
begin
    inherited Create;
    FIdHTTP := TIdHTTP.Create(nil);
    FIdHTTP.ConnectTimeout := FConTimeOut;
    FIdHTTP.ReadTimeout := FReadTimeOut;
    FIdHTTP.Request.ContentType := 'application/json';

    //FCon := TFDConnection.Create(nil);
    //PreparaConexaoFirebird(FCon);

    //FQuery := TFDQuery.Create(nil);
    //FQuery.Connection := FCon;
    //FQuery.SQL.Text := 'insert into PAYMENTS (CORRELATION_ID, AMOUNT, STATUS, PROCESSOR, CREATED_AT) ' +
    //                   'values (:CORRELATION_ID, :AMOUNT, :STATUS, :PROCESSOR, :CREATED_AT)';
end;

destructor TWorkerRequest.Destroy;
begin
    //if (FCon.Connected) then
    //    FCon.Close;

    FIdHTTP.Free;
    //FQuery.Free;
    //FCon.Free;

    inherited;
end;

{procedure TWorkerRequest.GarantirConexaoBD;
begin
    if (not FCon.Connected) then
    begin
        try
            FCon.Open;
        except
            on E: Exception do
            begin
                GerarLog('Erro ao abrir conexão: ' + E.Message);
            end;
        end;
    end;

    FUltimoUsoBD := Now;
end;

procedure TWorkerRequest.VerificarExpiracaoConexaoBD;
begin
    if FCon.Connected then
    begin
        if MinutesBetween(Now, FUltimoUsoBD) > 2 then
        begin
            try
                FCon.Close;
            except
                on E: Exception do
                begin
                    GerarLog('Erro ao fechar conexão: ' + E.Message);
                end;
            end;
        end;
    end;
end; }

{ TWorkerBD }

constructor TWorkerBD.Create;
begin
    inherited Create;
    FCon := TFDConnection.Create(nil);
    PreparaConexaoFirebird(FCon);

    FQuery := TFDQuery.Create(nil);
    FQuery.Connection := FCon;
    FQuery.SQL.Text := 'insert into PAYMENTS (CORRELATION_ID, AMOUNT, STATUS, PROCESSOR, CREATED_AT) ' +
                       'values (:CORRELATION_ID, :AMOUNT, :STATUS, :PROCESSOR, :CREATED_AT)';
end;

destructor TWorkerBD.Destroy;
begin
    if (FCon.Connected) then
        FCon.Close;

    FQuery.Free;
    FCon.Free;
    inherited;
end;

procedure TWorkerBD.GarantirConexaoBD;
begin
    if (not FCon.Connected) then
    begin
        try
            FCon.Open;
        except
            on E: Exception do
            begin
                GerarLog('Erro ao abrir conexão: ' + E.Message);
            end;
        end;
    end;

    FUltimoUsoBD := Now;
end;

procedure TWorkerBD.VerificarExpiracaoConexaoBD;
begin
    if FCon.Connected then
    begin
        if MinutesBetween(Now, FUltimoUsoBD) > 2 then
        begin
            try
                FCon.Close;
            except
                on E: Exception do
                begin
                    GerarLog('Erro ao fechar conexão: ' + E.Message);
                end;
            end;
        end;
    end;
end;

{ TFilaWorkerManager }

constructor TFilaWorkerManager.Create;
begin
    inherited Create;
    FListaWorker := TList<TWorker>.Create;
    FProcessamentoAtivo := False;
end;

destructor TFilaWorkerManager.Destroy;
begin
    Finalizar;
    FListaWorker.Free;
    inherited;
end;

procedure TFilaWorkerManager.EnfileirarTarefa(const ATarefa: TProc);
var
    lMenosCarregado: TWorker;
    liMenorFila: Integer;
    lWorker: TWorker;
begin
    liMenorFila := MaxInt;
    lMenosCarregado := nil;

    for lWorker in FListaWorker do
    begin
        if lWorker.QtdeItens < liMenorFila then
        begin
            liMenorFila := lWorker.QtdeItens;
            lMenosCarregado := lWorker;
        end;
    end;

    if Assigned(lMenosCarregado) then
        lMenosCarregado.EnfileirarTarefa(ATarefa);
end;

procedure TFilaWorkerManager.Finalizar;
var
    lWorker: TWorker;
begin
    FProcessamentoAtivo := False;

    for lWorker in FListaWorker do
        lWorker.Finalizar;

    FListaWorker.Clear;
end;

procedure TFilaWorkerManager.Iniciar(const AQtdeWorkers: Integer);
var
    I: Integer;
    lWorker: TWorker;
begin
    if FProcessamentoAtivo then
        Exit;

    FProcessamentoAtivo := True;

    for I := 1 to AQtdeWorkers do
    begin
        lWorker := TWorker.Create;
        FListaWorker.Add(lWorker);
    end;
end;

function TFilaWorkerManager.QtdeItens: Integer;
var
    liTotal, I: Integer;
begin
    liTotal := 0;
    for I := 0 to FListaWorker.Count - 1 do
        Inc(liTotal, FListaWorker[I].QtdeItens);

    Result := liTotal;
end;

{ TFilaWorkerRequest }

constructor TFilaWorkerRequest.Create;
begin
    inherited Create;
    FListaWorker := TList<TWorkerRequest>.Create;
    FProcessamentoAtivo := False;
end;

destructor TFilaWorkerRequest.Destroy;
begin
    Finalizar;
    FListaWorker.Free;
    inherited;
end;

procedure TFilaWorkerRequest.EnfileirarTarefa(const ATarefa: TProc);
var
    lMenosCarregado: TWorkerRequest;
    liMenorFila: Integer;
    lWorker: TWorkerRequest;
begin
    liMenorFila := MaxInt;
    lMenosCarregado := nil;

    for lWorker in FListaWorker do
    begin
        if lWorker.QtdeItens < liMenorFila then
        begin
            liMenorFila := lWorker.QtdeItens;
            lMenosCarregado := lWorker;
        end;
    end;

    if Assigned(lMenosCarregado) then
        lMenosCarregado.EnfileirarTarefa(ATarefa);
end;

procedure TFilaWorkerRequest.Finalizar;
var
    lWorker: TWorkerRequest;
begin
    FProcessamentoAtivo := False;

    for lWorker in FListaWorker do
        lWorker.Finalizar;

    FListaWorker.Clear;
end;

procedure TFilaWorkerRequest.Iniciar(const AQtdeWorkers: Integer);
var
    I: Integer;
    lWorker: TWorkerRequest;
begin
    if FProcessamentoAtivo then Exit;
        FProcessamentoAtivo := True;

    for I := 1 to AQtdeWorkers do
    begin
        lWorker := TWorkerRequest.Create;
        FListaWorker.Add(lWorker);
    end;
end;

function TFilaWorkerRequest.QtdeItens: Integer;
var
    liTotal, I: Integer;
begin
    liTotal := 0;
    for I := 0 to FListaWorker.Count - 1 do
        Inc(liTotal, FListaWorker[I].QtdeItens);

    Result := liTotal;
end;

{ TFilaWorkerBD }

constructor TFilaWorkerBD.Create;
begin
    inherited Create;
    FListaWorker := TList<TWorkerBD>.Create;
    FProcessamentoAtivo := False;
end;

destructor TFilaWorkerBD.Destroy;
begin
    Finalizar;
    FListaWorker.Free;
    inherited;
end;

procedure TFilaWorkerBD.EnfileirarTarefa(const ATarefa: TProc);
var
    lMenosCarregado: TWorkerBD;
    liMenorFila: Integer;
    lWorker: TWorkerBD;
begin
    liMenorFila := MaxInt;
    lMenosCarregado := nil;

    for lWorker in FListaWorker do
    begin
        if lWorker.QtdeItens < liMenorFila then
        begin
            liMenorFila := lWorker.QtdeItens;
            lMenosCarregado := lWorker;
        end;
    end;

    if Assigned(lMenosCarregado) then
        lMenosCarregado.EnfileirarTarefa(ATarefa);
end;

procedure TFilaWorkerBD.Finalizar;
var
    lWorker: TWorkerBD;
begin
    FProcessamentoAtivo := False;

    for lWorker in FListaWorker do
        lWorker.Finalizar;

    FListaWorker.Clear;
end;

procedure TFilaWorkerBD.Iniciar(const AQtdeWorkers: Integer);
var
    I: Integer;
    lWorker: TWorkerBD;
begin
    if FProcessamentoAtivo then Exit;
        FProcessamentoAtivo := True;

    for I := 1 to AQtdeWorkers do
    begin
        lWorker := TWorkerBD.Create;
        FListaWorker.Add(lWorker);
    end;
end;

function TFilaWorkerBD.QtdeItens: Integer;
var
    liTotal, I: Integer;
begin
    liTotal := 0;
    for I := 0 to FListaWorker.Count - 1 do
        Inc(liTotal, FListaWorker[I].QtdeItens);

    Result := liTotal;
end;

end.
