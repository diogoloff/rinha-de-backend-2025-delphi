object dmServer: TdmServer
  OldCreateOrder = False
  OnCreate = DataModuleCreate
  Height = 271
  Width = 415
  object DSServer: TDSServer
    Left = 96
    Top = 11
  end
  object DSServerPagamentos: TDSServerClass
    OnGetClass = DSServerPagamentosGetClass
    Server = DSServer
    Left = 208
    Top = 11
  end
  object FDManagerRinha: TFDManager
    WaitCursor = gcrNone
    FormatOptions.AssignedValues = [fvMapRules]
    FormatOptions.OwnMapRules = True
    FormatOptions.MapRules = <>
    ResourceOptions.AssignedValues = [rvKeepConnection]
    ResourceOptions.KeepConnection = False
    UpdateOptions.AssignedValues = [uvLockMode]
    UpdateOptions.LockMode = lmPessimistic
    Left = 96
    Top = 72
  end
  object FDGUIxWaitCursor1: TFDGUIxWaitCursor
    Provider = 'Console'
    ScreenCursor = gcrNone
    Left = 208
    Top = 140
  end
  object FDPhysFBDriverLink1: TFDPhysFBDriverLink
    Left = 208
    Top = 73
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
    Left = 96
    Top = 144
  end
  object IdHTTPPagamentos: TIdHTTP
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
    Left = 96
    Top = 200
  end
end
