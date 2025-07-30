unit unsmPagamentos;

interface

uses System.SysUtils, System.Classes, System.Json, System.DateUtils,
    System.RegularExpressions, System.SyncObjs,
    DataSnap.DSProviderDataModuleAdapter, Datasnap.DSServer, Datasnap.DSAuth, REST.HttpClient,
    FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Stan.Async,
    FireDAC.DApt, FireDAC.Phys.FB, FireDAC.Phys.FBDef,
    FireDAC.Stan.Option, Data.DB, IdHTTP, undmServer, FireDAC.Stan.Intf, FireDAC.Stan.Param, FireDAC.Stan.Error, FireDAC.DatS, FireDAC.Phys.Intf,
    FireDAC.DApt.Intf, FireDAC.Comp.DataSet, IdBaseComponent, IdComponent, IdTCPConnection, IdTCPClient;

type
  TsmPagamentos = class(TDSServerModule)
    QyInserePagamento: TFDQuery;
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

uses unErroHelper, unDBHelper, unConstantes;

function TsmPagamentos.EnviarPagamento(const JSON: string): String;
var
    ljObj: TJSONObject;
    ldDataCriacao: TDateTime;

    correlationId: string;
    amount: Double;
    requestedAt: string;
begin
    ljObj := nil;
    try
        try
            ljObj := TJSONObject.ParseJSONValue(JSON) as TJSONObject;
            correlationId := ljObj.GetValue('correlationId').Value;
            amount := StrToFloat(ljObj.GetValue('amount').Value);
        except
            on E : Exception do
            begin
                GerarLog('Validação JSON: ' + E.Message, True);
                Exit(ErroJson('Json Mal Formado'));
            end;
        end;
    finally
        ljObj.Free;
    end;

    try
        ldDataCriacao := Now;
        requestedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', TTimeZone.Local.ToUniversalTime(ldDataCriacao));

        FFilaLock.Enter;
        try
            FFilaEnvio.Add(TRequisicaoPendente.Create(correlationId, amount, requestedAt));
        finally
            FFilaLock.Leave;
        end;
    except
        on E : Exception do
        begin
            GerarLog('Erro Requisição: ' + E.Message, True);
            Exit(ErroInterno('Erro Interno Requisição'));
        end;
    end;

    Result := '{}';

    //Result := '{"success":{"code":200}}';

    // simulação da lógica de comunicação com os Processors
    {processor := 'na';
    status := 'error';
    lbResultado := False;
    lbContinua := True;

    if (FDefaultAtivo) then
    begin
        processor := 'default';
        lbResultado := EnviarParaProcessar(correlationId, amount, requestedAt, True);

        if (not lbResultado) then
        begin
            processor := 'fallback';
            lbResultado := EnviarParaProcessar(correlationId, amount, requestedAt, False);

            if (lbResultado) then
            begin
                FMonitorLock.Enter;
                try
                    FDefaultAtivo := False;
                finally
                    FMonitorLock.Leave;
                end;
            end;
        end;
    end
    else
    begin
        processor := 'fallback';
        lbResultado := EnviarParaProcessar(correlationId, amount, requestedAt, False);

        if (not lbResultado) then
        begin
            processor := 'default';
            lbResultado := EnviarParaProcessar(correlationId, amount, requestedAt, True);

            if (lbResultado) then
            begin
                FMonitorLock.Enter;
                try
                    FDefaultAtivo := True;
                finally
                    FMonitorLock.Leave;
                end;
            end;
        end;
    end;

    if (not lbResultado) then
    begin
        FFilaLock.Enter;
        try
            FFilaReenvio.Add(TRequisicaoPendente.Create(correlationId, amount, requestedAt));
        finally
            FFilaLock.Leave;
        end;
    end;

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
                GerarLog(E.Message, True);
                Exit(ErroInterno('Não foi possivel gravar o registro do pagamento'));
            end;
        end;
    finally
        DestruirConexaoFirebird(lCon);
    end; }

    //if (not lbResultado) then
    //    Exit(ErroInterno('Não foi possivel processar o pagamento'));

    //Result := '{"status":"' + status + '","message":"Pagamento processado"}'
end;

function TsmPagamentos.ObterResumoPagamentos(const FromISO, ToISO: string): String;
var
    lCon: TFDConnection;
    qry: TFDQuery;
    sqlWhere: string;
    TotalDefault, TotalFallback: Integer;
    AmountDefault, AmountFallback: Double;
    FS: TFormatSettings;
begin
    //lCon := CriarConexaoFirebird;
    //qry := TFDQuery.Create(nil);
    try
        //qry.Connection := lCon;

        try
            // Monta WHERE dinâmico
            {sqlWhere := '';
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
            qry.Open;  }

            TotalDefault := 0;
            AmountDefault := 0.0;

            TotalFallback := 0;
            AmountFallback := 0.0;

            {while not qry.Eof do
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
            end;  }

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
                GerarLog(E.Message, True);
            end;
        end;
    finally
        //qry.Free;
        //DestruirConexaoFirebird(lCon);
    end;
end;

end.

