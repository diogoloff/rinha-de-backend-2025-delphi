unit unDBHelper;

interface

uses
  System.SysUtils, System.Classes,
  FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Stan.Async,
  FireDAC.DApt, FireDAC.Phys.FB, FireDAC.Phys.FBDef, FireDAC.Stan.Pool,
  FireDAC.Stan.Option, Data.DB, undmServer;

function CriarConexaoFirebird: TFDConnection;
function ParametrosBanco: TStringList;
procedure DestruirConexaoFirebird(var lCon: TFDConnection);

implementation

function CriarConexaoFirebird: TFDConnection;
var
    lCon: TFDConnection;
begin
    lCon := nil;
    try
        lCon := TFDConnection.Create(nil);
        lCon.DriverName := 'FB';
        lCon.ConnectionDefName := 'RINHA';
        lCon.LoginPrompt := False;
        lCon.TxOptions.AutoStop := False;
        lCon.TxOptions.DisconnectAction := xdRollback;
        lCon.UpdateOptions.UpdateMode := upWhereKeyOnly;
        lCon.UpdateOptions.LockMode := lmPessimistic;
        lCon.ResourceOptions.KeepConnection := False;

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
        Add('POOL_MaximumItems=50');
        Add('Database=/var/lib/firebird/data/banco.fdb');
        Add('User_Name=SYSDBA');
        Add('Password=masterkey');
        Add('DriverID=FB');
        Add('Protocol=TCPIP');
        Add('Server=192.168.0.4');
        Add('Port=3051');
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
