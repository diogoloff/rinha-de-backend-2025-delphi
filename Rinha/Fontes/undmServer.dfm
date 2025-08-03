object dmServer: TdmServer
  OldCreateOrder = False
  OnCreate = DataModuleCreate
  OnDestroy = DataModuleDestroy
  Height = 271
  Width = 415
  object DSServer: TDSServer
    ChannelQueueSize = 500
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
    Active = True
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
end
