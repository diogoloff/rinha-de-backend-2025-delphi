unit unErroHelper;

interface

uses
    System.SysUtils;

function ErroJson(const AMensagem: string): string;
function ErroInterno(const AMensagem: string): string;

implementation

function ErroJson(const AMensagem: string): string;
begin
    Result := Format('{"error":{"code":400,"message":"%s"}}', [AMensagem]);
end;

function ErroInterno(const AMensagem: string): string;
begin
    Result := Format('{"error":{"code":500,"message":"%s"}}', [AMensagem]);
end;

end.
