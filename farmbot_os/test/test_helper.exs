Application.ensure_all_started(:mimic)
Mimic.copy(Avrdude.MuonTrapAdapter)
Mimic.copy(FarmbotCore.Asset)
Mimic.copy(FarmbotCore.FarmwareRuntime)
Mimic.copy(FarmbotCore.LogExecutor)
Mimic.copy(FarmbotExt.API.Reconciler)
Mimic.copy(FarmbotExt.API)
Mimic.copy(FarmbotFirmware)
Mimic.copy(FarmbotOS.Configurator.ConfigDataLayer)
Mimic.copy(FarmbotOS.Configurator.DetsTelemetryLayer)
Mimic.copy(FarmbotOS.Configurator.FakeNetworkLayer)
ExUnit.start()
