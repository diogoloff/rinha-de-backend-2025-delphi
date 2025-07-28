unit unsmPagamentos;

interface

uses System.SysUtils, System.Classes, System.Json, System.DateUtils, System.RegularExpressions,
    DataSnap.DSProviderDataModuleAdapter, Datasnap.DSServer, Datasnap.DSAuth, REST.HttpClient,
    FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Stan.Async,
    FireDAC.DApt, FireDAC.Phys.FB, FireDAC.Phys.FBDef,
    FireDAC.Stan.Option, Data.DB, IdHTTP, undmServer, FireDAC.Stan.Intf, FireDAC.Stan.Param, FireDAC.Stan.Error, FireDAC.DatS, FireDAC.Phys.Intf,
    FireDAC.DApt.Intf, FireDAC.Comp.DataSet;

type
  TsmPagamentos = class(TDSServerModule)
    QyInserePagamento: TFDQuery;
  private
    function EnviarParaProcessar(const correlationId: string; const amount: Double; const requestedAt: string; const default: Boolean): Boolean;
    { Private declarations }
  public
    { Public declarations }
    function EnviarPagamento([JSONParam] const JSON: string): String;
    function ObterResumoPagamentos(const FromISO, ToISO: string): String;
  end;

implementation

{%CLASSGROUP 'System.Classes.TPersistent'}

{$R *.dfm}

uses unErroHelper, unHealthHelper, unDBHelper, unConstantes;

function TsmPagamentos.EnviarParaProcessar(const correlationId: string; const amount: Double; const requestedAt: string; const default: Boolean): Boolean;
var
    lHTTP: TIdHTTP;
    ljEnviar: TJSONObject;
    lsResposta: string;
    lsURL : String;
    lStream: TStringStream;
begin
    Result := False;

    lsURL := cURL + '/payments';
    if (not default) then
        lsURL := cURLFall + '/payments';

    lHTTP := TIdHTTP.Create(nil);
    ljEnviar := TJSONObject.Create;
    try
        try
            // Monta o corpo JSON
            ljEnviar.AddPair('correlationId', correlationId);
            ljEnviar.AddPair('amount', TJSONNumber.Create(amount));
            ljEnviar.AddPair('requestedAt', requestedAt);

            lStream := TStringStream.Create(ljEnviar.ToString, TEncoding.UTF8);

            lHTTP.Request.ContentType := 'application/json';

            // Envia a requisição POST
            lsResposta :=
                lHTTP.Post(
                    lsURL,
                    lStream
                );

            // Se chegou aqui sem exceção, assume sucesso
            Result := True;
        except
            on E: Exception do
            begin
                GerarLog(E.Message, True);
                Result := False;
            end;
        end;
    finally
        ljEnviar.Free;
        lHTTP.Free;

        if Assigned(lStream) then
            lStream.Free;
    end;
end;

function TsmPagamentos.EnviarPagamento([JSONParam] const JSON: string): String;
var
    ljObj: TJSONObject;
    lCon: TFDConnection;
    ldDataCriacao: TDateTime;
    lbResultado: boolean;

    correlationId: string;
    amount: Double;
    requestedAt: string;
    status: string;
    processor: string;
begin
    try
        // Tenta converter o JSON para objeto
        ljObj := TJSONObject.ParseJSONValue(JSON) as TJSONObject;
        if not Assigned(ljObj) then
            Exit(ErroJson('JSON inválido.'));

        // Extrai o campo correlationId
        if not ljObj.TryGetValue('correlationId', correlationId) then
            Exit(ErroJson('Campo "correlationId" ausente.'));

        // Verifica se é um UUID válido
        if not TRegEx.IsMatch(correlationId, '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') then
            Exit(ErroJson('Formato de "correlationId" inválido.'));

        // Extrai o campo amount
        if not ljObj.TryGetValue('amount', amount) then
            Exit(ErroJson('Campo "amount" ausente.'));

        if amount <= 0 then
            Exit(ErroJson('Campo "amount" deve ser maior que zero.'));
    finally
        ljObj.Free;
    end;

    ldDataCriacao := Now;
    requestedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', TTimeZone.Local.ToUniversalTime(ldDataCriacao));

    // simulação da lógica de comunicação com os Processors
    processor := 'na';
    status := 'error';
    lbResultado := False;

    if (CheckHealth = 0) then
    begin
        processor := 'default';
        lbResultado := EnviarParaProcessar(correlationId, amount, requestedAt, True);
    end
    else if (CheckHealth = 1) then
    begin
        processor := 'fallback';
        lbResultado := EnviarParaProcessar(correlationId, amount, requestedAt, True);
    end;

    if (lbResultado) then
        status := 'success';

    lCon := CriarConexaoFirebird;
    QyInserePagamento.Connection := lCon;
    try
        try
            if (lCon.InTransaction) then
                lCon.Rollback;

            lCon.StartTransaction;

            with QyInserePagamento do
            begin
                Close;
                Params.ParamByName('correlation_id').AsString := correlationId;
                Params.ParamByName('amount').AsFloat := amount;
                Params.ParamByName('status').AsString := status;
                Params.ParamByName('processor').AsString := processor;
                Params.ParamByName('created_at').AsDateTime := ldDataCriacao;
                ExecSQL;
            end;

            lCon.Commit;
        except
            on E : Exception do
            begin
                lCon.Rollback;
                Exit(ErroInterno('Não foi possivel gravar o registro do pagamento'));
            end;
        end;
    finally
        DestruirConexaoFirebird(lCon);
    end;

    if (not lbResultado) then
        Exit(ErroInterno('Não foi possivel processar o pagamento'));

    Result := '{"status":"' + status + '","message":"Pagamento processado"}'
end;

function TsmPagamentos.ObterResumoPagamentos(const FromISO, ToISO: string): String;
var
    conn: TFDConnection;
    qry: TFDQuery;
    sqlWhere: string;
    TotalDefault, TotalFallback: Integer;
    AmountDefault, AmountFallback: Double;
    FS: TFormatSettings;
begin
    conn := CriarConexaoFirebird;
    qry := TFDQuery.Create(nil);
    try
        qry.Connection := conn;

        // Monta WHERE dinâmico
        sqlWhere := '';
        if FromISO <> '' then
            sqlWhere := sqlWhere + ' AND created_at >= :from ';

        if ToISO <> '' then
            sqlWhere := sqlWhere + ' AND created_at <= :to ';

        // Consulta com agregação por processor
        qry.SQL.Text :=
            'SELECT processor, COUNT(*) AS totalRequests, SUM(amount) AS totalAmount ' +
            'FROM payments WHERE status = ''success'' ' + sqlWhere +
            'GROUP BY processor';

        if FromISO <> '' then
            qry.ParamByName('from').AsDateTime := ISO8601ToDate(FromISO);

        if ToISO <> '' then
            qry.ParamByName('to').AsDateTime := ISO8601ToDate(ToISO);

        // Executa e processa o resultado
        qry.Open;

        TotalDefault := 0;
        AmountDefault := 0.0;

        TotalFallback := 0;
        AmountFallback := 0.0;

        while not qry.Eof do
        begin
            if qry.FieldByName('processor').AsString = 'default' then
            begin
                TotalDefault := qry.FieldByName('totalRequests').AsInteger;
                AmountDefault := qry.FieldByName('totalAmount').AsFloat;
            end
            else
            begin
                TotalFallback := qry.FieldByName('totalRequests').AsInteger;
                AmountFallback := qry.FieldByName('totalAmount').AsFloat;
            end;

            qry.Next;
        end;

        FS := TFormatSettings.Create;
        FS.DecimalSeparator := '.';

        Result :=
            '{ "default": { "totalRequests": ' + IntToStr(TotalDefault) +
            ', "totalAmount": ' + FormatFloat('0.00', AmountDefault, FS) + ' }, ' +
            '"fallback": { "totalRequests": ' + IntToStr(TotalFallback) +
            ', "totalAmount": ' + FormatFloat('0.00', AmountFallback, FS) + ' } }';

    finally
        qry.Free;
        DestruirConexaoFirebird(conn);
    end;
end;

end.

