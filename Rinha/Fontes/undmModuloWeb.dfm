object dmModuloWeb: TdmModuloWeb
  OldCreateOrder = False
  OnCreate = WebModuleCreate
  Actions = <
    item
      Default = True
      Name = 'DefaultHandler'
      PathInfo = '/'
      OnAction = WebModule1DefaultHandlerAction
    end
    item
      MethodType = mtPost
      Name = 'EnviarPagamento'
      PathInfo = '/payments'
      OnAction = dmModuloWebPaymentsAction
    end
    item
      MethodType = mtGet
      Name = 'ObterResumoPagamentos'
      PathInfo = '/payments-summary'
      OnAction = dmModuloWebObterResumoPagamentosAction
    end>
  BeforeDispatch = WebModuleBeforeDispatch
  AfterDispatch = WebModuleAfterDispatch
  Height = 333
  Width = 414
  object DSRESTWebDispatcher1: TDSRESTWebDispatcher
    DSContext = '/'
    RESTContext = '/'
    Left = 96
    Top = 75
  end
end
