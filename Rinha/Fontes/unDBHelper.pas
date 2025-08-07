unit unDBHelper;

interface

uses
    System.SysUtils, System.Classes,
    FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Stan.Async,
    FireDAC.DApt, FireDAC.Phys.FB, FireDAC.Phys.FBDef, FireDAC.Stan.Pool,
    FireDAC.Stan.Option, Data.DB, unGenerica;

    procedure PreparaConexaoFirebird(ACon: TFDConnection);
    function CriarConexaoFirebird: TFDConnection;
    function ParametrosBanco: TStringList;
    procedure DestruirConexaoFirebird(var lCon: TFDConnection);

implementation

procedure PreparaConexaoFirebird(ACon: TFDConnection);
begin
    //ACon.DriverName := 'FB';
    ACon.ConnectionDefName := 'RINHA';
    ACon.LoginPrompt := False;
    ACon.TxOptions.AutoCommit := False;
    ACon.TxOptions.AutoStop := False;
    ACon.TxOptions.DisconnectAction := xdRollback;
    ACon.UpdateOptions.UpdateMode := upWhereKeyOnly;
    ACon.UpdateOptions.LockMode := lmPessimistic;
    ACon.ResourceOptions.KeepConnection := False;
end;

function CriarConexaoFirebird: TFDConnection;
var
    lCon: TFDConnection;
begin
    lCon := TFDConnection.Create(nil);
    try
        PreparaConexaoFirebird(lCon);
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
        Add('POOL_CleanupTimeout=5');  // Removido pois a desconexão agora esta sendo manual
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
