unit unsmPagamentos;

interface

uses System.SysUtils, System.Classes, System.Json, System.DateUtils,
    DataSnap.DSProviderDataModuleAdapter, Datasnap.DSServer, Datasnap.DSAuth, REST.HttpClient,
    FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Stan.Async,
    FireDAC.DApt, FireDAC.Phys.FB, FireDAC.Phys.FBDef,
    FireDAC.Stan.Option, Data.DB, FireDAC.Stan.Intf, FireDAC.Stan.Param, FireDAC.Stan.Error,
    FireDAC.DatS, FireDAC.Phys.Intf, FireDAC.DApt.Intf, FireDAC.Comp.DataSet,
    unGenerica, unRequisicaoPendente, unDBHelper, unLogHelper, unSchedulerHelper;

type
  TsmPagamentos = class(TDSServerModule)
  private
    { Private declarations }
  public
    { Public declarations }
    function EnviarPagamento(const JSON: string): String;
    function ObterResumoPagamentos(const FromISO, ToISO: string): String;
  end;

implementation

{%CLASSGROUP 'System.Classes.TPersistent'}

{$R *.dfm}

function TsmPagamentos.EnviarPagamento(const JSON: string): String;
var
    ljObj: TJSONObject;
    correlationId: string;
    amount: Double;
    requestedAt: string;
    ltReq: TRequisicaoPendente;
begin
    ljObj := nil;
    try
        ljObj := TJSONObject.ParseJSONValue(JSON) as TJSONObject;
        correlationId := ljObj.GetValue('correlationId').Value;
        amount := StrToFloat(ljObj.GetValue('amount').Value);
        requestedAt := DateToISO8601(Now, True);
    finally
        ljObj.Free;
    end;

    ltReq := TRequisicaoPendente.Create(correlationId, amount, requestedAt);

    // Antes de adicionar o worker talvez seria importante ver quantos itens tem na fila e de alguma forma gerar uma espécie de timeout
    // minimo para segurar as novas requisições até a fila aliviar novamente

    //LiberaCarga;

    AdicionarWorker(ltReq);

    Result := '';
end;

function TsmPagamentos.ObterResumoPagamentos(const FromISO, ToISO: string): String;
var
    lCon: TFDConnection;
    sqlWhere: string;
    TotalDefault, TotalFallback: Integer;
    AmountDefault, AmountFallback: Double;
    FS: TFormatSettings;
    QyPagto: TFDQuery;
begin
    lCon := CriarConexaoFirebird;
    QyPagto := TFDQuery.Create(nil);
    try
        QyPagto.Connection := lCon;

        try
            // Monta WHERE dinâmico
            sqlWhere := '';
            if FromISO <> '' then
                sqlWhere := sqlWhere + ' AND created_at >= :from ';

            if ToISO <> '' then
                sqlWhere := sqlWhere + ' AND created_at <= :to ';

            // Consulta com agregação por processor
            QyPagto.SQL.Text :=
                'SELECT processor, COUNT(*) AS totalRequests, SUM(amount) AS totalAmount ' +
                'FROM payments WHERE status = ''success'' ' + sqlWhere +
                'GROUP BY processor';

            if FromISO <> '' then
                QyPagto.ParamByName('from').AsDateTime := ISO8601ToDate(FromISO);

            if ToISO <> '' then
                QyPagto.ParamByName('to').AsDateTime := ISO8601ToDate(ToISO);

            // Executa e processa o resultado
            QyPagto.Open;

            TotalDefault := 0;
            AmountDefault := 0.0;

            TotalFallback := 0;
            AmountFallback := 0.0;

            while not QyPagto.Eof do
            begin
                if QyPagto.FieldByName('processor').AsString = 'default' then
                begin
                    TotalDefault := QyPagto.FieldByName('totalRequests').AsInteger;
                    AmountDefault := QyPagto.FieldByName('totalAmount').AsFloat;
                end
                else
                begin
                    TotalFallback := QyPagto.FieldByName('totalRequests').AsInteger;
                    AmountFallback := QyPagto.FieldByName('totalAmount').AsFloat;
                end;

                QyPagto.Next;
            end;

            FS := TFormatSettings.Create;
            FS.DecimalSeparator := '.';

            Result :=
                '{ "default": { "totalRequests": ' + IntToStr(TotalDefault) +
                ', "totalAmount": ' + FormatFloat('0.00', AmountDefault, FS) + ' }, ' +
                '"fallback": { "totalRequests": ' + IntToStr(TotalFallback) +
                ', "totalAmount": ' + FormatFloat('0.00', AmountFallback, FS) + ' } }';
        except
            on E : Exception do
            begin
                GerarLog(E.Message);
            end;
        end;
    finally
        QyPagto.Free;
        DestruirConexaoFirebird(lCon);
    end;
end;

end.

