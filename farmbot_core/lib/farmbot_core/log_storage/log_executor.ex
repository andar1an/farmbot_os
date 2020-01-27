# This module could have existed within FarmbotCore.Logger.
# Pulling this function into a different module facilitates
# mocking of tests.
defmodule FarmbotCore.LogExecutor do
  alias FarmbotCore.Log

  def execute(%Log{} = log) do
    logger_meta = [
      application: :farmbot,
      function: log.function,
      file: log.file,
      line: log.line,
      module: log.module,
      channels: log.meta[:channels] || log.meta["channels"],
      verbosity: log.verbosity,
      assertion_passed: log.meta[:assertion_passed]
    ]

    level = log.level

    logger_level =
      if level in [:info, :debug, :warn, :error],
        do: level,
        else: :info

    Elixir.Logger.bare_log(logger_level, log, logger_meta)
    log
  end
end
