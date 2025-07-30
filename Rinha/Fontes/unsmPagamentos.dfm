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
end
