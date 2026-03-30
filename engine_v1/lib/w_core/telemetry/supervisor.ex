defmodule WCore.Telemetry.Supervisor do
  @moduledoc """
  Supervisor da árvore de processos de telemetria.
  """
  use Supervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
      WCore.Telemetry.TelemetryServer,
      WCore.Telemetry.WriteWorker,
      WCore.Telemetry.Simulator
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
