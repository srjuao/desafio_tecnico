defmodule WCore.TelemetryCase do
  @moduledoc """
  Case base para testes que precisam de ETS e GenServers isolados.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import WCore.TelemetryCase
      alias WCore.Telemetry.{TelemetryServer, WriteWorker, Cache}
    end
  end

  setup do
    # Garante que a tabela ETS não existe antes do teste
    if :ets.whereis(:w_core_telemetry_cache) != :undefined do
      :ets.delete(:w_core_telemetry_cache)
    end

    # Inicia os processos isolados para este teste
    start_supervised!(WCore.Telemetry.TelemetryServer)
    start_supervised!(WCore.Telemetry.WriteWorker)

    # Checkout do banco para este processo de teste
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(WCore.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(WCore.Repo, {:shared, self()})

    :ok
  end
end
