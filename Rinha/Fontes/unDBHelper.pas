unit unDBHelper;

interface

uses
    System.SysUtils, System.Classes,
    FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Stan.Async,
    FireDAC.DApt, FireDAC.Phys.FB, FireDAC.Phys.FBDef, FireDAC.Stan.Pool,
    FireDAC.Stan.Option, Data.DB, unGenerica;

    function CriarConexaoFirebird: TFDConnection;
    function ParametrosBanco: TStringList;
    procedure DestruirConexaoFirebird(var lCon: TFDConnection);

implementation

function CriarConexaoFirebird: TFDConnection;
var
    lCon: TFDConnection;
begin
    lCon := TFDConnection.Create(nil);
    try
        //lCon.DriverName := 'FB';
        lCon.ConnectionDefName := 'RINHA';
        lCon.LoginPrompt := False;
        lCon.TxOptions.AutoCommit := True;
        lCon.TxOptions.AutoStop := False;
        {lCon.TxOptions.DisconnectAction := xdRollback;
        lCon.UpdateOptions.UpdateMode := upWhereKeyOnly;
        lCon.UpdateOptions.LockMode := lmPessimistic;
        lCon.ResourceOptions.KeepConnection := False;}
        lCon.Connected := True;
        Result := lCon;
    except
        on E: Exception do
        begin
            if Assigned(lCon) then
                lCon.Free;

            raise Exception.Create('Erro ao conectar ao banco: ' + E.Message);
        end;
    end;
end;

function ParametrosBanco: TStringList;
begin
    Result := TStringList.Create;

    with Result do
    begin
        Add('Pooled=True');
        Add('POOL_MaximumItems=500');
        Add('POOL_CleanupTimeout=5');
        Add('ReadConsistency=True');
        Add('Database=/var/lib/firebird/data/' + GetEnv('DB_NAME', 'banco.fdb'));
        Add('User_Name=' + GetEnv('DB_USER', 'SYSDBA'));
        Add('Password=' + GetEnv('DB_PASS', 'masterkey'));
        Add('DriverID=FB');
        Add('Protocol=TCPIP');
        Add('Server=' + GetEnv('DB_HOST', 'localhost'));
        Add('Port=' + GetEnv('DB_PORT', '3050'));
        Add('SQLDialect=3');
        Add('CharacterSet=UTF8');
    end;
end;

procedure DestruirConexaoFirebird(var lCon: TFDConnection);
begin
    if Assigned(lCon) then
    begin
        try
            if lCon.Connected then
                lCon.Connected := False;
        except
            on E: Exception do
            begin
                GerarLog(E.Message, True);
            end;
        end;

        lCon.Free;
        lCon := nil;
    end;
end;

end.
