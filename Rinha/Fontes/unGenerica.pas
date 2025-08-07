unit unGenerica;

interface

uses
    System.SysUtils, System.SyncObjs, System.IOUtils, System.DateUtils;

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
    FTamahoFila: Integer;
    FNumTentativasDefault: Integer;

implementation

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
            if (trim(FPathAplicacao) = '') then
                FPathAplicacao := '/opt/rinha/';

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
    FConTimeOut := StrToIntDef(GetEnv('CON_TIME_OUT', ''), 2500);
    FReadTimeOut := StrToIntDef(GetEnv('READ_TIME_OUT', ''), 2500);
    FResTimeOut := StrToIntDef(GetEnv('RES_TIME_OUT', ''), 100);
    FNumMaxWorkersFila := StrToIntDef(GetEnv('NUM_WORKERS_FILA', ''), 2);
    FNumMaxWorkersProcesso := StrToIntDef(GetEnv('NUM_WORKERS_PROCESSO', ''), 8);
    FTempoFila := StrToIntDef(GetEnv('TEMPO_FILA', ''), 500);
    FTamahoFila := StrToIntDef(GetEnv('TAMANHO_FILA', ''), 500);
    FNumTentativasDefault := StrToIntDef(GetEnv('NUM_TENTATIVAS_DEFAULT', ''), 5);

     if (FConTimeOut < 10) or (FConTimeOut > 5000) then
        FConTimeOut := 2500;

    if (FReadTimeOut < 100) or (FReadTimeOut > 5000) then
        FReadTimeOut := 2500;

    if (FResTimeOut < 100) or (FResTimeOut > 5000) then
        FResTimeOut := 100;

    if (FNumMaxWorkersFila < 2) or (FNumMaxWorkersFila > 50) then
        FNumMaxWorkersFila := 25;

    if (FNumMaxWorkersProcesso < 2) or (FNumMaxWorkersProcesso > 100) then
        FNumMaxWorkersProcesso := 50;

    if (FTempoFila < 100) or (FTempoFila > 1000) then
        FTempoFila := 500;

    if (FTamahoFila < 100) or (FTamahoFila > 1000) then
        FTamahoFila := 500;

    if (FNumTentativasDefault < 1) then
        FNumTentativasDefault := 1;

end;

initialization
    FLogLock := TCriticalSection.Create;

finalization
    FLogLock.Free;

end.
