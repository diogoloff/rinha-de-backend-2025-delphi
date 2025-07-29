program Rinha;
{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  IdHTTPWebBrokerBridge,
  Web.WebReq,
  Web.WebBroker,
  {$IFDEF LINUX64}
  WiRL.Console.Posix.Daemon,
  WiRL.Console.Posix.Syslog,
  {$ENDIF }
  unsmPagamentos in 'Fontes\unsmPagamentos.pas' {smPagamentos: TDSServerModule},
  undmServer in 'Fontes\undmServer.pas' {dmServer: TDataModule},
  undmModuloWeb in 'Fontes\undmModuloWeb.pas' {dmModuloWeb: TWebModule},
  unConstantes in 'Fontes\unConstantes.pas',
  unErroHelper in 'Fontes\unErroHelper.pas',
  unHealthHelper in 'Fontes\unHealthHelper.pas',
  unDBHelper in 'Fontes\unDBHelper.pas';

{$R *.res}

var
    LServer : TIdHTTPWebBrokerBridge;

    {$IFDEF LINUX64}
        FTipoServico : TTypeService;
    {$ENDIF}
begin
    {$IFDEF DEBUG}
        ReportMemoryLeaksOnShutdown := True;
    {$ENDIF}

    DefaultSystemCodePage := 65001;

    {$IFDEF SERVICO}
        if (Trim(UpperCase(Copy(ParamStr(1), 1, 6))) <> '-PATH:') then
        begin
            writeln('Não foi o parâmetro de passagem -PATH! Informe como primeiro parâmetro -PATH:CAMINHO FISICO DA APLICACAO');
            Exit;
        end;

        FPathAplicacao := (Trim(Copy(ParamStr(1), 7, length(ParamStr(1)) - 6)));

        if (trim(FPathAplicacao) = '') then
        begin
            writeln('Não foi informado o path da aplicação como parametro de passagem -PATH!');
            Exit;
        end;
    {$ENDIF}

    try
        if WebRequestHandler <> nil then
            WebRequestHandler.WebModuleClass := WebModuleClass;

        LServer := TIdHTTPWebBrokerBridge.Create(nil);

        try
            LServer.DefaultPort := 8080;

            if FindCmdLineSwitch('DAEMON', ['-'], true) then
            begin
                {$IFDEF LINUX64}
                    if ((trim(ParamStr(3)) = 'S')) then
                        FTipoServico := TTypeService.tsSimple
                    else if ((trim(ParamStr(3)) = 'E')) then
                        FTipoServico := TTypeService.tsExec
                    else if ((trim(ParamStr(3)) = 'N')) then
                        FTipoServico := TTypeService.tsNotify
                    else if ((trim(ParamStr(3)) = 'F')) then
                        FTipoServico := TTypeService.tsForking
                    else
                        FTipoServico := TTypeService.tsForkingManual;

                    FSobrescreveDefineServico := False;
                    TPosixDaemon.Setup(
                        procedure(ASignal: TPosixSignal)
                        begin
                            case ASignal of
                                TPosixSignal.Termination:
                                begin
                                    TPosixDaemon.LogInfo('Rinha Termination ' + TimeToStr(Time));
                                end;

                                TPosixSignal.Reload:
                                begin
                                    TPosixDaemon.LogInfo('Rinha Reload ' + TimeToStr(Time));
                                end;

                                TPosixSignal.User1:
                                begin
                                    TPosixDaemon.LogInfo('Rinha User1 ' + TimeToStr(Time));
                                end;

                                TPosixSignal.User2:
                                begin
                                    TPosixDaemon.LogInfo('Rinha User2');
                                end;
                            end;
                        end,
                        FPathAplicacao,
                        FTipoServico
                    );

                    RunDSServer(LServer);

                    if (not FServerIniciado) then
                      Halt(TPosixDaemon.EXIT_FAILURE);

                    FPidFile := '';
                    if FindCmdLineSwitch('pidfile', ['-'], true) then
                    begin
                        FPidFile := trim(ParamStr(5));
                        TPosixDaemon.CreatePIDFile(FPidFile);
                    end;

                    TPosixDaemon.Run(1000);

                    StopServer(LServer);

                    if (Trim(FPidFile) <> '') then
                        TPosixDaemon.RemovePIDFile(FPidFile);
                {$ENDIF}
            end
            else
            begin
                {$IFDEF LINUX64}
                FSobrescreveDefineServico := True;
                {$ENDIF}

                writeln('##############################################');

                {$IFDEF LINUX64}
                    writeln('Rinha iniciado como aplicação, caso deseje iniciar como serviço informe como segundo parâmetro -DAEMON!');
                {$ELSE}
                    writeln('Rinha iniciado como aplicação!');
                {$ENDIF}

                writeln('##############################################');
                RunDSServer(LServer);
                writeln('Rinha finalizado!');
            end;

            TerminateThreads;
        finally
            LServer.Free;
        end;
    except
        on E: Exception do
            Writeln(E.ClassName, ': ', E.Message);
    end;
end.
