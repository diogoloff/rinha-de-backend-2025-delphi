unit unDBHelper;

interface

uses
  System.SysUtils,
  FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Stan.Async,
  FireDAC.DApt, FireDAC.Phys.FB, FireDAC.Phys.FBDef, FireDAC.Stan.Pool,
  FireDAC.Stan.Option, Data.DB, undmServer;

function CriarConexaoFirebird: TFDConnection;
procedure DestruirConexaoFirebird(var conn: TFDConnection);

implementation

function CriarConexaoFirebird: TFDConnection;
var
    conn: TFDConnection;
begin
    conn := nil;
    try
        conn := TFDConnection.Create(nil);
        conn.DriverName := 'FB';
        conn.ConnectionDefName := 'RINHA';

        with conn.Params do
        begin
            Add('Pooled=True');
            Add('POOL_MaximumItems=50');
            Add('Database=C:\Projetos\Rinha\BD\BDRINHA.FDB');
            Add('User_Name=SYSDBA');
            Add('Password=masterkey');
            Add('DriverID=FB');
            Add('Protocol=TCPIP');
            Add('Server=localhost');
            Add('Port=3050');
            Add('SQLDialect=3');
            Add('CharacterSet=UTF8');
        end;

        conn.LoginPrompt := False;
        conn.TxOptions.AutoStop := False;
        conn.TxOptions.DisconnectAction := xdRollback;
        conn.UpdateOptions.UpdateMode := upWhereKeyOnly;
        conn.UpdateOptions.LockMode := lmPessimistic;
        conn.ResourceOptions.KeepConnection := False;

        conn.Connected := True;
        Result := conn;
    except
        on E: Exception do
        begin
            if Assigned(conn) then
                conn.Free;

            raise Exception.Create('Erro ao conectar ao banco: ' + E.Message);
        end;
    end;
end;

procedure DestruirConexaoFirebird(var conn: TFDConnection);
begin
    if Assigned(conn) then
    begin
        try
            if conn.Connected then
                conn.Connected := False;
        except
            on E: Exception do
            begin
                GerarLog(E.Message, True);
            end;
        end;

        conn.Free;
        conn := nil;
    end;
end;

end.
