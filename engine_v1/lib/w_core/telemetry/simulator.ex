defmodule WCore.Telemetry.Simulator do
  @moduledoc """
  Simulador de tráfego industrial de alta frequência.
  Lê os nodes gravados e periodicamente efetua o envio de pacotes
  simulando telemetria de sensores, bombardeando o GenServer ETS.
  """
  use GenServer
  alias WCore.Telemetry
  alias WCore.Telemetry.TelemetryServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    # Dá 2 segundos para a aplicação inicializar por completo
    Process.send_after(self(), :tick, 2000)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    nodes = Telemetry.list_nodes()

    # Para cada sensor cadastrado, dispara um evento aleatório simulando IoT
    for node <- nodes do
      status = Enum.random([
        "online", "online", "online", "online", "online",
        "warning", "warning", "critical"
      ])

      # Dados individuais de acordo com o tipo de máquina
      payload =
        cond do
          String.contains?(node.machine_identifier, "GERADOR") ->
            %{"voltage" => Enum.random(215..238), "current" => Enum.random(40..60), "frequency" => Float.round(60.0 + (:rand.uniform() - 0.5), 2)}
          String.contains?(node.machine_identifier, "CALDEIRA") ->
            %{"pressure" => Float.round(Float.round(Enum.random(10..20) + :rand.uniform(), 2), 2), "temperature" => Enum.random(150..200), "water_level" => Enum.random(70..95)}
          String.contains?(node.machine_identifier, "TURBINA") ->
            %{"rpm" => Enum.random(3000..3600), "vibration" => Float.round(Enum.random(1..15) / 10.0, 2), "oil_pressure" => Enum.random(40..60)}
          String.contains?(node.machine_identifier, "COMPRESSOR") ->
            %{"air_pressure" => Enum.random(100..150), "flow_rate" => Enum.random(500..800), "motor_temp" => Enum.random(60..90)}
          String.contains?(node.machine_identifier, "ESTEIRA") ->
            %{"speed" => Float.round(Enum.random(1..5) + :rand.uniform(), 2), "load" => Enum.random(200..800), "belt_tension" => Enum.random(50..100)}
          true ->
            %{"temperature" => Enum.random(30..120), "rpm" => Enum.random(1000..3500), "vibration" => Enum.random(1..10) / 10.0}
        end

      # Geração de picos anômalos
      {status, payload} =
        if status == "critical" do
           payload = Map.new(payload, fn {k, v} -> {k, if(is_float(v), do: Float.round(v * 1.5, 2), else: round(v * 1.5))} end)
           {status, payload}
        else
          {status, payload}
        end

      TelemetryServer.ingest(node.id, status, payload)
    end

    # Pulsa novamente em um intervalo de 1 a 3 segundos (caos)
    Process.send_after(self(), :tick, Enum.random(1000..3000))
    
    {:noreply, state}
  end
end
