unit undmServer;

interface

uses System.SysUtils, System.Classes, System.IOUtils,
  Datasnap.DSServer, Datasnap.DSCommonServer, Datasnap.DSAuth, Datasnap.DSSession,
  IPPeerServer, IPPeerAPI, IdHTTPWebBrokerBridge, FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.UI.Intf, FireDAC.Phys.Intf,
  FireDAC.Stan.Def, FireDAC.Phys, FireDAC.Comp.Client, FireDAC.ConsoleUI.Wait, FireDAC.Phys.FBDef, FireDAC.Phys.IBBase, FireDAC.Phys.FB, FireDAC.Comp.UI;

type
  TdmServer = class(TDataModule)
    DSServer: TDSServer;
    DSServerPagamentos: TDSServerClass;
    FDManagerRinha: TFDManager;
    FDGUIxWaitCursor1: TFDGUIxWaitCursor;
    FDPhysFBDriverLink1: TFDPhysFBDriverLink;
    procedure DSServerPagamentosGetClass(DSServerClass: TDSServerClass;
      var PersistentClass: TPersistentClass);
    procedure DataModuleCreate(Sender: TObject);
  private
    procedure PreparaConexaoBanco;
    { Private declarations }
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

function DSServer: TDSServer;

procedure TerminateThreads;
procedure RunDSServer(const AServer: TIdHTTPWebBrokerBridge);
procedure StopServer(const AServer: TIdHTTPWebBrokerBridge);
procedure GerarLog(lsMsg : String; lbForcaArquivo : Boolean = False; lbQuebraLinhaConsole : Boolean = True);

var
    FModule: TComponent;
    FDSServer: TDSServer;
    FPathAplicacao : String;

    {$IFDEF SERVICO}
        FServerIniciado: Boolean;
    {$ENDIF}

    {$IFDEF LINUX64}
        FSobrescreveDefineServico: Boolean;
        FPidFile : String;
    {$ENDIF}

implementation

{%CLASSGROUP 'System.Classes.TPersistent'}

{$R *.dfm}

uses
    unsmPagamentos, unConstantes;

function DSServer: TDSServer;
begin
    Result := FDSServer;
end;

constructor TdmServer.Create(AOwner: TComponent);
begin
    inherited;
    FDSServer := DSServer;
end;

procedure TdmServer.PreparaConexaoBanco;
var
    oParams: TStringList;
begin
    FDManager.Active := False;

    oParams := TStringList.Create;
    try
        with oParams do
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

        if (not FDManager.IsConnectionDef('RINHA')) then
            FDManager.AddConnectionDef('RINHA', 'FB', oParams)
        else
            FDManager.ModifyConnectionDef('RINHA', oParams)
    finally
        FreeAndNil(oParams);
    end;

    FDManager.Active := True;
end;

procedure TdmServer.DataModuleCreate(Sender: TObject);
begin
    PreparaConexaoBanco;
end;

destructor TdmServer.Destroy;
begin
    inherited;
    FDSServer := nil;
end;

procedure TdmServer.DSServerPagamentosGetClass(
  DSServerClass: TDSServerClass; var PersistentClass: TPersistentClass);
begin
    PersistentClass := unsmPagamentos.TsmPagamentos;
end;

function BindPort(APort: Integer): Boolean;
var
    LTestServer: IIPTestServer;
begin
    Result := True;
    try
        LTestServer := PeerFactory.CreatePeer('', IIPTestServer) as IIPTestServer;
        LTestServer.TestOpenPort(APort, nil);
        LTestServer := nil;
    except
        on E : Exception do
        begin
            GerarLog('- Teste de porta: ' + E.Message, True);
            Result := False;
        end;
    end;
end;

function CheckPort(Aport: Integer): Integer;
begin
    if BindPort(Aport) then
        Result := Aport
    else
        Result := 0;
end;

procedure WriteCommands;
begin
    GerarLog(sCommands);
    GerarLog(cArrow, False, False);
end;

procedure StartServer(const AServer: TIdHTTPWebBrokerBridge);
begin
    if not AServer.Active then
    begin
        if CheckPort(AServer.DefaultPort) > 0 then
        begin
            GerarLog(Format(sStartingServer, [AServer.DefaultPort]));
            AServer.Bindings.Clear;
            AServer.Active := True;
        end
        else
            GerarLog(Format(sPortInUse, [AServer.DefaultPort.ToString]));
    end
    else
        GerarLog(sServerRunning);

    GerarLog(cArrow);
end;

procedure TerminateThreads;
begin
    if TDSSessionManager.Instance <> nil then
        TDSSessionManager.Instance.TerminateAllSessions;
end;

procedure StopServer(const AServer: TIdHTTPWebBrokerBridge);
begin
    if AServer.Active then
    begin
        GerarLog(sStoppingServer);
        TerminateThreads;
        AServer.Active := False;
        AServer.Bindings.Clear;
        GerarLog(sServerStopped);
    end
    else
        GerarLog(sServerNotRunning);
    GerarLog(cArrow);
end;

procedure WriteStatus(const AServer: TIdHTTPWebBrokerBridge);
begin
    GerarLog(sIndyVersion + AServer.SessionList.Version);
    GerarLog(sActive + AServer.Active.ToString(TUseBoolStrs.True));
    GerarLog(sPort + AServer.DefaultPort.ToString);
    GerarLog(sSessionID + AServer.SessionIDCookieName);
    GerarLog(cArrow);
end;

procedure RunDSServer(const AServer: TIdHTTPWebBrokerBridge);
    procedure ModoConsole;
    var
        LResponse: string;
    begin
        // Modelo Console
        WriteCommands;
        while True do
        begin
            Readln(LResponse);
            LResponse := LowerCase(LResponse);
            if sametext(LResponse, cCommandStart) then
                StartServer(AServer)
            else if sametext(LResponse, cCommandStatus) then
                WriteStatus(AServer)
            else if sametext(LResponse, cCommandStop) then
                StopServer(AServer)
            else if sametext(LResponse, cCommandHelp) then
                WriteCommands
            else if sametext(LResponse, cCommandExit) then
                if AServer.Active then
                begin
                    StopServer(AServer);
                    break
                end
                else
                    break
            else
            begin
                Writeln(sInvalidCommand);
                Write(cArrow);
            end;
        end;
    end;
begin
    {$IFDEF SERVICO}
        FServerIniciado := False;
    {$ENDIF}

    {$IFNDEF LINUX64}
        FPathAplicacao := ExtractFilePath(ParamStr(0));
    {$ENDIF}

    {$IFNDEF SERVICO}
        ModoConsole;
    {$ELSE}
        // Esta condição de aplica ao linux onde não é possivel tratar as duas opções por define
        {$IFDEF LINUX64}
            if (FSobrescreveDefineServico) then
            begin
                ModoConsole;
                Exit;
            end;
        {$ENDIF}

        // Modelo serviço
        try
            StartServer(AServer);

            FServerIniciado := True;
        except
            on E : Exception do
            begin
                GerarLog(E.Message, True);
            end;
        end;
    {$ENDIF}
end;

procedure GerarLog(lsMsg : String; lbForcaArquivo : Boolean; lbQuebraLinhaConsole : Boolean);
var
    lsArquivo : String;
begin
    {$IFNDEF SERVICO}
        if (lbQuebraLinhaConsole) then
            Writeln(lsMsg)
        else
            Write(lsMsg);
    {$ELSE}
        {$IFDEF LINUX64}
            if (FSobrescreveDefineServico) then
            begin
                if (lbQuebraLinhaConsole) then
                    Writeln(lsMsg)
                else
                    Write(lsMsg);
            end;
        {$ENDIF}
    {$ENDIF}

    if (lbForcaArquivo) then
    begin
        try
            if (not DirectoryExists(FPathAplicacao + 'Logs')) then
                CreateDir(FPathAplicacao + 'Logs');

            lsArquivo := FPathAplicacao + 'Logs' + PathDelim + 'log' + FormatDateTime('ddmmyyyy', Date) + '.txt';

            TFile.AppendAllText(lsArquivo, TimeToStr(Now) + ':' + lsMsg + sLineBreak, TEncoding.UTF8);
        except
        end;
    end;
end;

initialization
    FModule := TdmServer.Create(nil);

finalization
    FModule.Free;
end.

