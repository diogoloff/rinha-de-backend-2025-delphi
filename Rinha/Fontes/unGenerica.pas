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
    FNumMaxRetain: Integer;
    FNumMaxWorkers: Integer;
    FDetalAdaptativo: Integer;

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
    FNumMaxRetain := StrToIntDef(GetEnv('QTDE_MAX_RETAIN', ''), 500);
    FNumMaxWorkers := StrToIntDef(GetEnv('NUM_WORKERS', ''), 2);
    FDetalAdaptativo := StrToIntDef(GetEnv('DELTA', ''), 4);

     if (FConTimeOut < 10) or (FConTimeOut > 100) then
        FConTimeOut := 50;

    if (FReadTimeOut < 100) or (FReadTimeOut > 5000) then
        FReadTimeOut := 3000;

    if (FResTimeOut < 100) or (FResTimeOut > 5000) then
        FResTimeOut := 1000;

    if (FNumMaxRetain < 100) or (FNumMaxRetain > 1000) then
        FNumMaxRetain := 250;

    if (FNumMaxWorkers < 2) or (FNumMaxWorkers > 2000) then
        FNumMaxWorkers := 2;

    if (FDetalAdaptativo < 1) or (FDetalAdaptativo > 9) then
        FDetalAdaptativo := 4;
end;

initialization
    FLogLock := TCriticalSection.Create;

finalization
    FLogLock.Free;

end.
