unit unsmPagamentos;

interface

uses System.SysUtils, System.Classes, System.Json, System.DateUtils,
    System.RegularExpressions, System.SyncObjs,
    DataSnap.DSProviderDataModuleAdapter, Datasnap.DSServer, Datasnap.DSAuth, REST.HttpClient,
    FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Stan.Async,
    FireDAC.DApt, FireDAC.Phys.FB, FireDAC.Phys.FBDef,
    FireDAC.Stan.Option, Data.DB, undmServer, FireDAC.Stan.Intf, FireDAC.Stan.Param, FireDAC.Stan.Error,
    FireDAC.DatS, FireDAC.Phys.Intf, FireDAC.DApt.Intf, FireDAC.Comp.DataSet;

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
    correlationId: string;
    amount: Double;
    requestedAt: string;
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

    FFilaLock.Enter;
    try
        FFilaEnvio.Add(TRequisicaoPendente.Create(correlationId, amount, requestedAt));
    finally
        FFilaLock.Leave;
    end;

    Result := '';

    FEventoFila.SetEvent;
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

