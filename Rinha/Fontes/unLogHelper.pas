unit unLogHelper;

interface

uses
    System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections, System.IOUtils, System.TypInfo, System.DateUtils, unGenerica;

type
    TStatusFila = (sfSucesso, sfTimeout, sfErro500, sfErroDesconhecido, sfDescartado, sfSalvo);

    TFilaLogEntry = record
        ID: string;
        Entrada: TDateTime;
        Reentrada: Integer;
        UltimaExecucao: TDateTime;
        StatusFinal: TStatusFila;
        LatenciaTotal: Integer;
    end;

    TFilaLogger = class
    private
        FLog: TDictionary<string, TFilaLogEntry>;
    public
        constructor Create;
        destructor Destroy; override;

        procedure LogEntrada(const AID: string);
        procedure LogExecucao(const AID: string; AStatus: TStatusFila; ALatencia: Integer);
        procedure GerarRelatorioFinal;
    end;

var
    FilaLogger: TFilaLogger;

implementation

{ TFilaLogger }

constructor TFilaLogger.Create;
begin
    FLog := TDictionary<string, TFilaLogEntry>.Create;
end;

destructor TFilaLogger.Destroy;
begin
    FLog.Free;
    inherited;
end;

procedure TFilaLogger.GerarRelatorioFinal;
var
    Entry: TFilaLogEntry;
    ReportLines: TStringList;
    Linha: string;
begin
    ReportLines := TStringList.Create;
    try
        for Entry in FLog.Values do
        begin
            Linha := Format('ID=%s | Reentradas=%d | Latência=%dms | Status=%s | Entrada=%s | ÚltimaExecução=%s',
              [Entry.ID, Entry.Reentrada, Entry.LatenciaTotal,
               GetEnumName(TypeInfo(TStatusFila), Ord(Entry.StatusFinal)),
               FormatDateTime('hh:nn:ss.zzz', Entry.Entrada),
               FormatDateTime('hh:nn:ss.zzz', Entry.UltimaExecucao)]);

            ReportLines.Add(Linha);
        end;

        if (ReportLines.Count > 0) then
            TFile.WriteAllText('/opt/rinha/Logs/fila-relatorio.txt', ReportLines.Text, TEncoding.UTF8);
    finally
        ReportLines.Free;
    end;
end;

procedure TFilaLogger.LogEntrada(const AID: string);
var
    Entry: TFilaLogEntry;
begin
    if (not FDebug) then
        Exit;

    if FLog.ContainsKey(AID) then
    begin
        Entry := FLog[AID];
        Inc(Entry.Reentrada);
        FLog[AID] := Entry;
    end
    else
    begin
        Entry.ID := AID;
        Entry.Entrada := Now;
        Entry.Reentrada := 0;
        FLog.Add(AID, Entry);
    end;
end;

procedure TFilaLogger.LogExecucao(const AID: string; AStatus: TStatusFila; ALatencia: Integer);
var
    Entry: TFilaLogEntry;
begin
    if (not FDebug) then
        Exit;

    if FLog.TryGetValue(AID, Entry) then
    begin
        if (AStatus = sfDescartado) or (AStatus = sfSalvo) then
            ALatencia := MilliSecondsBetween(Now, Entry.Entrada);

        Entry.UltimaExecucao := Now;
        Entry.LatenciaTotal := ALatencia;
        Entry.StatusFinal := AStatus;
        FLog[AID] := Entry;
    end;
end;

initialization
    FilaLogger := TFilaLogger.Create;

finalization
    FilaLogger.GerarRelatorioFinal;

end.
