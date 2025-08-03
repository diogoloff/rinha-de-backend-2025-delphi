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
    if (not FDebug) then
        Exit;

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
    FNumMaxRetain := StrToIntDef(GetEnv('NUM_MAX_RETAIN', ''), 500);
    FNumMaxWorkers := StrToIntDef(GetEnv('NUM_WORKERS', ''), 1000);
end;

initialization
    FLogLock := TCriticalSection.Create;

finalization
    FLogLock.Free;

end.
