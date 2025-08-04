unit unHealthHelper;

interface

uses
    System.Classes, System.SysUtils, System.SyncObjs, System.JSON, System.DateUtils,
    IdBaseComponent, IdComponent, IdTCPConnection, IdTCPClient, IdHTTP,
    unGenerica, unWorkerHelper, System.Generics.Collections, System.Math;

type
    TServiceHealthMonitor = class
    private
        FEventoVerificar: TEvent;
        FMonitorLock: TCriticalSection;
        FDefaultAtivo: Integer;
        FTempoMinimoResposta: Integer;
        FTempoMinimoRespostaPadrao : Integer;
        FTempoMaximoRespostaPadrao : Integer;
        FUltimaVerificacao: TDateTime;
        FHealthURL: string;
        FMonitoramentoAtivo: Boolean;
        FIdHTTP: TIdHTTP;
        FFilaCongestionada: Integer;
        FUltimoBloqueio: TDateTime;
        FQtdeMaxRetencao: Integer;
        FThreadMonitorar: TThread;

        procedure ThreadMonitorar;
        procedure ExecutarHealthCheck;
    function TempoMinimoBloqueioAdaptativo: Double;
    public
        constructor Create(const AHealthURL: string; const AConTimeOut: Integer; const AReadTimeOut: Integer; const AResTimeOut: Integer; const AQtdeMaxRetain: Integer);
        destructor Destroy; override;

        procedure Iniciar;
        procedure Finalizar;
        procedure VerificarSinal;

        function GetDefaultAtivo: Boolean;
        function GetTempoMinimoResposta: Integer;
        function GetTempoMaximoRespostaPadrao: Integer;
        function GetFilaCongestionada: Boolean;
        function GetUltimoBloqueio: TDateTime;
        procedure SetDefaultAtivo(const AValue: Boolean);
        procedure SetTempoMinimoResposta(const AValue: Integer);
        procedure SetFilaCongestionada(const AValue: Boolean);
        procedure SetUltimoBloqueio(const AValue: TDateTime);
        function DeveSairDaContencao: Boolean;
    end;

    procedure IniciarHealthCk;
    procedure FinalizarHealthCk;

var
    ServiceHealthMonitor: TServiceHealthMonitor;

implementation

uses unScheduledHelper;

{ TServiceHealthMonitor }

constructor TServiceHealthMonitor.Create(const AHealthURL: string; const AConTimeOut: Integer; const AReadTimeOut: Integer; const AResTimeOut: Integer; const AQtdeMaxRetain: Integer);
begin
    FEventoVerificar := TEvent.Create(nil, False, False, '');
    FMonitorLock := TCriticalSection.Create;
    FDefaultAtivo := 1;
    FTempoMinimoResposta := AResTimeOut;
    FTempoMinimoRespostaPadrao := AResTimeOut;
    FTempoMaximoRespostaPadrao := AResTimeOut * 2;
    FUltimaVerificacao := IncSecond(Now, -6);
    FHealthURL := AHealthURL;
    FQtdeMaxRetencao := AQtdeMaxRetain;

    FIdHTTP := TIdHTTP.Create(nil);
    FIdHTTP.ConnectTimeout := AConTimeOut;
    FIdHTTP.ReadTimeout := AReadTimeOut;
    FIdHTTP.Request.ContentType := 'application/json';

    FMonitoramentoAtivo := True;
end;

destructor TServiceHealthMonitor.Destroy;
begin
    Finalizar;

    FEventoVerificar.Free;
    FMonitorLock.Free;
    FIdHTTP.Free;
    inherited;
end;

procedure TServiceHealthMonitor.ExecutarHealthCheck;
var
    lsResposta: string;
    ljResposta: TJSONObject;
    failing: Boolean;
    minResponseTime: Integer;

    procedure TestaServico;
    begin
        lsResposta := FIdHTTP.Get(FHealthURL + '/payments/service-health');
        ljResposta := TJSONObject.ParseJSONValue(lsResposta) as TJSONObject;

        if Assigned(ljResposta) then
        begin
            failing := ljResposta.GetValue('failing').Value = 'true';
            minResponseTime := StrToInt(ljResposta.GetValue('minResponseTime').Value);
            ljResposta.Free;
        end;

        GerarLog('Teste Serviço: F' + BoolToStr(failing, True) + ' T' + IntToStr(minResponseTime));
    end;
begin
    failing := False;
    minResponseTime := FTempoMinimoResposta;

    try
        TestaServico;
    except
        on E: Exception do
        begin
            GerarLog('Erro Servico ' +
                    ' - C:' + IntToStr(FConTimeOut) +
                    ' - R:' + IntToStr(FReadTimeOut) +
                    ' - RES:' + IntToStr(FTempoMinimoResposta) +
                    ' - Monitorar: ' + FHealthURL + ' - ' + E.Message);
        end;
    end;

    if (minResponseTime < FTempoMinimoRespostaPadrao) then
        minResponseTime := FTempoMinimoRespostaPadrao
    else
    begin
        if (minResponseTime > FTempoMaximoRespostaPadrao) then
            minResponseTime := FTempoMaximoRespostaPadrao;
    end;

    FIdHTTP.ReadTimeout := minResponseTime;

    SetDefaultAtivo(not failing);
    SetTempoMinimoResposta(minResponseTime)
end;

function TServiceHealthMonitor.GetDefaultAtivo: Boolean;
begin
    Result := FDefaultAtivo <> 0;
end;

procedure TServiceHealthMonitor.SetDefaultAtivo(const AValue: Boolean);
begin
    TInterlocked.Exchange(FDefaultAtivo, Ord(AValue));
end;

function TServiceHealthMonitor.GetTempoMaximoRespostaPadrao: Integer;
begin
    Result := FTempoMaximoRespostaPadrao;
end;

function TServiceHealthMonitor.GetTempoMinimoResposta: Integer;
begin
    Result := FTempoMinimoResposta;
end;

procedure TServiceHealthMonitor.SetTempoMinimoResposta(const AValue: Integer);
begin
    TInterlocked.Exchange(FTempoMinimoResposta, AValue);
end;

procedure TServiceHealthMonitor.VerificarSinal;
begin
    FMonitorLock.Enter;
    try
        if SecondsBetween(Now, FUltimaVerificacao) >= 5 then
            FEventoVerificar.SetEvent;
    finally
        FMonitorLock.Leave;
    end;
end;

procedure TServiceHealthMonitor.Iniciar;
begin
    FThreadMonitorar := TThread.CreateAnonymousThread(ThreadMonitorar);
    FThreadMonitorar.Start;
end;

procedure TServiceHealthMonitor.Finalizar;
begin
    if (not FMonitoramentoAtivo) then
        Exit;

    FMonitoramentoAtivo := False;
    FEventoVerificar.SetEvent;

    if Assigned(FThreadMonitorar) then
    begin
        FThreadMonitorar.WaitFor;
        FreeAndNil(FThreadMonitorar);
    end;
end;

procedure TServiceHealthMonitor.ThreadMonitorar;
var
    lbPrimeiro: Boolean;
    lEstadoEvento: TWaitResult;
begin
    lbPrimeiro := True;
    while FMonitoramentoAtivo do
    begin
        // Aguarda até ser sinalizado que precisa verificar o status do serviço
        {if FEventoVerificar.WaitFor(INFINITE) = wrSignaled then
        begin
            // Mesmo que sinalizado verifica que esta no tempo de verificar, já que existe limite de 5 segundos a cada verificação
            if SecondsBetween(Now, FUltimaVerificacao) >= 5 then
            begin
                FUltimaVerificacao := Now;
                ExecutarHealthCheck;
            end;
        end; }

        // Aguarda até 5 segundos pelo sinal
        if (lbPrimeiro) then
        begin
            lEstadoEvento := FEventoVerificar.WaitFor(INFINITE);
            lbPrimeiro := False;
        end
        else
            lEstadoEvento := FEventoVerificar.WaitFor(5000);

        // Se sinal recebido OU tempo limite passou, executa verificação
        if (lEstadoEvento = wrSignaled) or
           (SecondsBetween(Now, FUltimaVerificacao) >= 5) then
        begin
            FUltimaVerificacao := Now;
            ExecutarHealthCheck;
        end;

        // Verifica se pode sair da contenção
        if (GetFilaCongestionada) then
        begin
            if (DeveSairDaContencao) then
            begin
                SetFilaCongestionada(False);
                GerarLog('Fila descongestionada automaticamente pelo monitor.');
            end;
        end;
    end;
end;

procedure TServiceHealthMonitor.SetFilaCongestionada(const AValue: Boolean);
begin
    TInterlocked.Exchange(Integer(FFilaCongestionada), Ord(AValue));

    if (AValue) then
    begin
        SetUltimoBloqueio(Now);
        GerarLog('Fila parada pelo sinal.');
    end;
end;

function TServiceHealthMonitor.GetFilaCongestionada: Boolean;
begin
    Result := FFilaCongestionada <> 0;
end;

procedure TServiceHealthMonitor.SetUltimoBloqueio(const AValue: TDateTime);
begin
    FMonitorLock.Enter;
    try
        FUltimoBloqueio := AValue;
    finally
        FMonitorLock.Leave;
    end;
end;

function TServiceHealthMonitor.GetUltimoBloqueio: TDateTime;
begin
    FMonitorLock.Enter;
    try
        Result := FUltimoBloqueio;
    finally
        FMonitorLock.Leave;
    end;
end;

function TServiceHealthMonitor.TempoMinimoBloqueioAdaptativo: Double;
var
    lfFatorLatencia, lfFatorWorkers, lfFatorFila: Double;
    lfTempoBase: Double;
    lLista: TList<TScheduledTask>;
begin
    lfFatorLatencia := Min(1, FTempoMinimoResposta / FTempoMaximoRespostaPadrao);
    lfFatorWorkers := 1 - Min(1, FilaWorkerManager.QtdeItens / FQtdeMaxRetencao);

    lLista := ListaDeAgendamentos.LockList;
    try
        lfFatorFila := Min(1, lLista.Count / FQtdeMaxRetencao);
    finally
        ListaDeAgendamentos.UnlockList;
    end;

    // Tempo base mínimo: 1s | máximo: 3s | Delta 2
    // Tempo base mínimo: 1s | máximo: 5s | Delta 4
    // Tempo base mínimo: 1s | máximo: 10s | Delta 9
    lfTempoBase := 1 + (FDetalAdaptativo * lfFatorLatencia * lfFatorFila * (1 - lfFatorWorkers));

    Result := RoundTo(lfTempoBase, -2);
end;

function TServiceHealthMonitor.DeveSairDaContencao: Boolean;
begin
    Result := (SecondsBetween(Now, GetUltimoBloqueio) >= TempoMinimoBloqueioAdaptativo);

    if (Result) then
        GerarLog('Fila descongestionada por tempo.');
end;

procedure IniciarHealthCk;
begin
    ServiceHealthMonitor := TServiceHealthMonitor.Create(FUrl, FConTimeOut, FReadTimeOut, FResTimeOut, FNumMaxRetain);
    ServiceHealthMonitor.Iniciar;
    ServiceHealthMonitor.VerificarSinal;
end;

procedure FinalizarHealthCk;
begin
    if (Assigned(ServiceHealthMonitor)) then
        ServiceHealthMonitor.Free;
end;

end.
