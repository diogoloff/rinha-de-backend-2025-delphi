unit unsmPagamentos;

interface

uses System.SysUtils, System.Classes, System.Json, System.DateUtils,
    DataSnap.DSProviderDataModuleAdapter, Datasnap.DSServer, Datasnap.DSAuth, REST.HttpClient,
    FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Stan.Async,
    FireDAC.DApt, FireDAC.Phys.FB, FireDAC.Phys.FBDef,
    FireDAC.Stan.Option, Data.DB, FireDAC.Stan.Intf, FireDAC.Stan.Param, FireDAC.Stan.Error,
    FireDAC.DatS, FireDAC.Phys.Intf, FireDAC.DApt.Intf, FireDAC.Comp.DataSet,
    unGenerica, unRequisicaoPendente, unDBHelper, unLogHelper, unSchedulerHelper, unWorkerHelper;

type
  TsmPagamentos = class(TDSServerModule)
  private
    { Private declarations }
  public
    { Public declarations }
    function EnviarPagamento(const AJSON: string): String;
    function ObterResumoPagamentos(const AFrom, ATo: string): String;
  end;

implementation

{%CLASSGROUP 'System.Classes.TPersistent'}

{$R *.dfm}

function TsmPagamentos.EnviarPagamento(const AJSON: string): String;
var
    ljObj: TJSONObject;
    correlationId: string;
    amount: Double;
    requestedAt: string;
    ltReq: TRequisicaoPendente;
begin
    ljObj := nil;
    try
        ljObj := TJSONObject.ParseJSONValue(AJSON) as TJSONObject;
        correlationId := ljObj.GetValue('correlationId').Value;
        amount := StrToFloat(ljObj.GetValue('amount').Value);
    finally
        ljObj.Free;
    end;

    ltReq := TRequisicaoPendente.Create(correlationId, amount, requestedAt);

    FilaLogger.LogEntrada(correlationId);

    {while GetObtendoLeitura do
        Sleep(1);   }

    AdicionarWorker(ltReq);

    Result := '';
end;

function TsmPagamentos.ObterResumoPagamentos(const AFrom, ATo: string): String;
var
    lCon: TFDConnection;
    lFS: TFormatSettings;
    lQuery: TFDQuery;
    lsSqlWhere: string;

    TotalDefault: Integer;
    TotalFallback: Integer;
    AmountDefault: Double;
    AmountFallback: Double;
begin
    lCon := CriarConexaoFirebird;
    lQuery := TFDQuery.Create(nil);
    try
        lQuery.Connection := lCon;

        try
            lsSqlWhere := '';
            if AFrom <> '' then
                lsSqlWhere := lsSqlWhere + ' AND created_at >= :from ';

            if ATo <> '' then
                lsSqlWhere := lsSqlWhere + ' AND created_at <= :to ';

            lQuery.SQL.Text :=
                'SELECT processor, COUNT(*) AS totalRequests, SUM(amount) AS totalAmount ' +
                'FROM payments WHERE status = ' + QuotedStr('success') + lsSqlWhere +
                'GROUP BY processor';

            if AFrom <> '' then
                lQuery.ParamByName('from').AsDateTime := ISO8601ToDate(AFrom);

            if ATo <> '' then
                lQuery.ParamByName('to').AsDateTime := ISO8601ToDate(ATo);

            {SetObtendoLeitura(True);

            while FilaWorkerBD.QtdeItens > 0 do
                Sleep(1); }

            lQuery.Open;

            TotalDefault := 0;
            AmountDefault := 0.0;

            TotalFallback := 0;
            AmountFallback := 0.0;

            while not lQuery.Eof do
            begin
                if lQuery.FieldByName('processor').AsString = 'default' then
                begin
                    TotalDefault := lQuery.FieldByName('totalRequests').AsInteger;
                    AmountDefault := lQuery.FieldByName('totalAmount').AsFloat;
                end
                else
                begin
                    TotalFallback := lQuery.FieldByName('totalRequests').AsInteger;
                    AmountFallback := lQuery.FieldByName('totalAmount').AsFloat;
                end;

                lQuery.Next;
            end;

            lFS := TFormatSettings.Create;
            lFS.DecimalSeparator := '.';

            Result :=
                '{ "default": { "totalRequests": ' + IntToStr(TotalDefault) +
                ', "totalAmount": ' + FormatFloat('0.00', AmountDefault, lFS) + ' }, ' +
                '"fallback": { "totalRequests": ' + IntToStr(TotalFallback) +
                ', "totalAmount": ' + FormatFloat('0.00', AmountFallback, lFS) + ' } }';

            //SetObtendoLeitura(False);
        except
            on E : Exception do
            begin
                GerarLog(E.Message);
            end;
        end;
    finally
        lQuery.Free;
        DestruirConexaoFirebird(lCon);
    end;
end;

end.

