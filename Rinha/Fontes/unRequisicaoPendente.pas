unit unRequisicaoPendente;

interface

uses
    System.SysUtils;

type
    TRequisicaoPendente = record
        correlationId: string;
        amount: Double;
        requestedAt: String;
        error: Boolean;
        attempt: Integer;
        createAt: TDateTime;
        executeAt: TDateTime;

        constructor Create(const AId: string; AAmount: Double; ARequestedAt: String);
    end;

implementation

{ TRequisicaoPendente }

constructor TRequisicaoPendente.Create(const AId: string; AAmount: Double; ARequestedAt: String);
begin
    correlationId := AId;
    amount := AAmount;
    requestedAt := ARequestedAt;
    error := False;
    attempt := 1;
    createAt := Now;
    executeAt := Now;
end;


end.
