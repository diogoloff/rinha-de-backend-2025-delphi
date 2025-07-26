unit unHealthHelper;

interface

uses
  System.SysUtils, IdHTTP, System.DateUtils, System.Json;

  function CheckDefaultHealth: Boolean;

var
    UltimoPingDefault: TDateTime = 0;
    UltimoStatusDefault: Boolean = True;

implementation

function CheckDefaultHealth: Boolean;
var
    HTTP: TIdHTTP;
    ResponseStr: String;
    ResponseJSON: TJSONObject;
    FailingValue: Boolean;
begin
    // Usa o último status se ainda estiver dentro do intervalo de 5 segundos
    if SecondsBetween(Now, UltimoPingDefault) < 5 then
        Exit(UltimoStatusDefault);

    // Atualiza o timestamp do último ping
    UltimoPingDefault := Now;

    HTTP := TIdHTTP.Create(nil);
    try
        try
            // Faz requisição ao endpoint de saúde do Processor Default
            ResponseStr := HTTP.Get('http://payment-processor-default:8080/payments/service-health');

            // Se não lançar exceção, está saudável
            ResponseJSON := TJSONObject.ParseJSONValue(ResponseStr) as TJSONObject;
            if Assigned(ResponseJSON) then
            begin
                if ResponseJSON.TryGetValue('failing', FailingValue) then
                    UltimoStatusDefault := not FailingValue
                else
                    UltimoStatusDefault := False;

                // Não vi utilização para o segundo parametro
                // var MinResponseTime: Integer;
                // if ResponseJSON.TryGetValue('minResponseTime', MinResponseTime) then
                //   // usar de alguma forma

                ResponseJSON.Free;
            end
            else
                UltimoStatusDefault := False;
        except
            // Em caso de erro, assume que está fora do ar
            on E: EIdHTTPProtocolException do
            begin
                // Se for erro 429, não atualiza o status, só respeita o cooldown
                if E.ErrorCode <> 429 then
                    UltimoStatusDefault := False;
            end;

            on E: Exception do
                UltimoStatusDefault := False;
        end;
    finally
        HTTP.Free;
    end;

    Result := UltimoStatusDefault;
end;

end.
