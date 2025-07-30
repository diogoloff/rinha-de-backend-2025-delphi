object smPagamentos: TsmPagamentos
  OldCreateOrder = False
  Height = 166
  Width = 156
  object QyInserePagamento: TFDQuery
    SQL.Strings = (
      
        'insert into PAYMENTS (CORRELATION_ID, AMOUNT, STATUS, PROCESSOR,' +
        ' CREATED_AT)'
      
        'values (:CORRELATION_ID, :AMOUNT, :STATUS, :PROCESSOR, :CREATED_' +
        'AT)  ')
    Left = 64
    Top = 32
    ParamData = <
      item
        Name = 'CORRELATION_ID'
        ParamType = ptInput
      end
      item
        Name = 'AMOUNT'
        ParamType = ptInput
      end
      item
        Name = 'STATUS'
        ParamType = ptInput
      end
      item
        Name = 'PROCESSOR'
        ParamType = ptInput
      end
      item
        Name = 'CREATED_AT'
        ParamType = ptInput
      end>
  end
  object IdHTTP: TIdHTTP
    AllowCookies = True
    ProxyParams.BasicAuthentication = False
    ProxyParams.ProxyPort = 0
    Request.ContentLength = -1
    Request.ContentRangeEnd = -1
    Request.ContentRangeStart = -1
    Request.ContentRangeInstanceLength = -1
    Request.Accept = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    Request.BasicAuthentication = False
    Request.UserAgent = 'Mozilla/3.0 (compatible; Indy Library)'
    Request.Ranges.Units = 'bytes'
    Request.Ranges = <>
    HTTPOptions = [hoForceEncodeParams]
    Left = 64
    Top = 88
  end
end
