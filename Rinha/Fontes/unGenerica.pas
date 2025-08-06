unit unGenerica;

interface

uses
    System.SysUtils, System.SyncObjs, System.IOUtils, System.DateUtils;

    function GetObtendoLeitura: Boolean;
    procedure SetObtendoLeitura(const AValue: Boolean);
    procedure CarregarVariaveisAmbiente;
    function GetEnv(const lsEnvVar, lsDefault: string): string;
    procedure GerarLog(lsMsg : String; lbQuebraLinhaConsole : Boolean = False);

var
    FPathAplicacao: String;

    {$IFDEF SERVICO}
        FServerIniciado: Boolean;
    {$ENDIF}

    {$IFDEF LINUX64}
        FPidFile : String;
    {$ENDIF}

    FLogLock: TCriticalSection;
    FDebug : Boolean;
    FUrl: String;
    FUrlFall: String;
    FConTimeOut: Integer;
    FReadTimeOut: Integer;
    FResTimeOut: Integer;
    FNumMaxWorkersFila: Integer;
    FNumMaxWorkersProcesso: Integer;
    FTempoFila: Integer;
    FObtendoLeitura: Integer;

implementation

procedure SetObtendoLeitura(const AValue: Boolean);
begin
    TInterlocked.Exchange(Integer(FObtendoLeitura), Ord(AValue));

    {if (AValue) then
    begin
        SetUltimoBloqueio(Now);
        GerarLog('Fila parada pelo sinal.');
    end;}
end;

function GetObtendoLeitura: Boolean;
begin
    Result := FObtendoLeitura <> 0;
end;

function GetEnv(const lsEnvVar, lsDefault: string): string;
begin
    Result := GetEnvironmentVariable(lsEnvVar);
    if Result = '' then
        Result := lsDefault;
end;

procedure GerarLog(lsMsg : String; lbQuebraLinhaConsole : Boolean);
var
    lsArquivo : String;
    lsData : String;
begin
    {$IFNDEF DEBUG}
        if (not FDebug) then
            Exit;
    {$ENDIF}

    {$IFNDEF SERVICO}
        if (lbQuebraLinhaConsole) then
            Writeln(lsMsg)
        else
            Write(lsMsg);
    {$ENDIF}

    FLogLock.Enter;
    try
        try
            lsData := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', TTimeZone.Local.ToUniversalTime(Now));
            lsArquivo := FPathAplicacao + 'Logs' + PathDelim +  'log' + FormatDateTime('ddmmyyyy', Date) + '.txt';
            TFile.AppendAllText(lsArquivo, lsData + ':' + lsMsg + sLineBreak, TEncoding.UTF8);
        except
        end;
     finally
        FLogLock.Leave;
     end;
end;

procedure CarregarVariaveisAmbiente;
begin
    FDebug := GetEnv('DEBUG', 'N') = 'S';
    FUrl := GetEnv('DEFAULT_URL', 'http://localhost:8001');
    FUrlFall := GetEnv('FALLBACK_URL', 'http://localhost:8002');
    FConTimeOut := StrToIntDef(GetEnv('CON_TIME_OUT', ''), 50);
    FReadTimeOut := StrToIntDef(GetEnv('READ_TIME_OUT', ''), 3500);
    FResTimeOut := StrToIntDef(GetEnv('RES_TIME_OUT', ''), 200);
    FNumMaxWorkersFila := StrToIntDef(GetEnv('NUM_WORKERS_FILA', ''), 2);
    FNumMaxWorkersProcesso := StrToIntDef(GetEnv('NUM_WORKERS_PROCESSO', ''), 2);
    FTempoFila := StrToIntDef(GetEnv('TEMPO_FILA', ''), 500);

     if (FConTimeOut < 10) or (FConTimeOut > 100) then
        FConTimeOut := 50;

    if (FReadTimeOut < 100) or (FReadTimeOut > 5000) then
        FReadTimeOut := 3000;

    if (FResTimeOut < 100) or (FResTimeOut > 5000) then
        FResTimeOut := 1000;

    if (FNumMaxWorkersFila < 2) or (FNumMaxWorkersFila > 2000) then
        FNumMaxWorkersFila := 4;

    if (FNumMaxWorkersProcesso < 2) or (FNumMaxWorkersProcesso > 2000) then
        FNumMaxWorkersProcesso := 25;

    if (FTempoFila < 100) or (FTempoFila > 1000) then
        FTempoFila := 500;
end;

initialization
    FLogLock := TCriticalSection.Create;

finalization
    FLogLock.Free;

end.
