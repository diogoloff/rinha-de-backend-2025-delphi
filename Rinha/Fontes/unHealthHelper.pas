unit unHealthHelper;

interface

uses
  System.SysUtils, IdHTTP, System.DateUtils, System.Json, System.SyncObjs,
  unConstantes, undmServer;

  function CheckHealth: Integer;

var
    FCSHealth: TCriticalSection;
    FUltimoPingDefault: TDateTime = 0;
    FUltimoRetorno: Integer = 0;

implementation

function AmbienteAtivo(const URL: string; out AmbienteOk: Boolean; out MinRT: Integer): Boolean;
var
    lHTTP: TIdHTTP;
    lsResposta: string;
    ljResposta: TJSONObject;
    lbFailing: Boolean;
begin
    Result := False;
    MinRT := MaxInt;
    AmbienteOk := False;

    lHTTP := TIdHTTP.Create(nil);
    try
        try
            lsResposta := lHTTP.Get(URL + '/payments/service-health');
            ljResposta := TJSONObject.ParseJSONValue(lsResposta) as TJSONObject;
            if Assigned(ljResposta) then
            begin
                if ljResposta.TryGetValue('failing', lbFailing) then
                    AmbienteOk := not lbFailing;

                ljResposta.TryGetValue('minResponseTime', MinRT);

                ljResposta.Free;
                Result := True;
            end;
        except
          on E: Exception do
          begin
              GerarLog('Erro ao verificar ambiente: ' + URL + ' - ' + E.Message, True);
          end;
        end;
    finally
        lHTTP.Free;
    end;
end;

function CheckHealth: Integer;
var
    lbDefaultAtivo : Boolean;
    lbFallbackAtivo : Boolean;
    liRTDefault : Integer;
    liRTFallback : Integer;
    ldUltPingTemp : TDateTime;
    liRetornoTemp : Integer;
begin
    FCSHealth.Enter;
    try
        if SecondsBetween(Now, FUltimoPingDefault) < 5 then
            Exit(FUltimoRetorno);

        ldUltPingTemp := Now;
    finally
        FCSHealth.Leave;
    end;

    liRetornoTemp := -1;
    AmbienteAtivo(FUrl, lbDefaultAtivo, liRTDefault);

    if (lbDefaultAtivo) then
        liRetornoTemp := 0;

    if (not lbDefaultAtivo) or (liRTDefault > 150) then
    begin
        AmbienteAtivo(FUrlFall, lbFallbackAtivo, liRTFallback);

        if (lbFallbackAtivo) then
        begin
            liRetornoTemp := 1;
            if (lbDefaultAtivo) and (liRTFallback > liRTDefault) then
                liRetornoTemp := 0;
        end;
    end;

    FCSHealth.Enter;
    try
        FUltimoRetorno := liRetornoTemp;
        FUltimoPingDefault := ldUltPingTemp;
    finally
        FCSHealth.Leave;
    end;

    Result := liRetornoTemp;
end;

initialization
  FCSHealth := TCriticalSection.Create;

finalization
  FCSHealth.Free;

end.
