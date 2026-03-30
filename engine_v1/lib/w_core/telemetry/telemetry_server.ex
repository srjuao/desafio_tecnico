defmodule WCore.Telemetry.TelemetryServer do
  @moduledoc """
  Coração do sistema de ingestão em tempo real.

  Responsabilidades:
    - Receber eventos (heartbeats) dos sensores via call/cast
    - Gravar/atualizar o estado no ETS imediatamente (sem tocar no banco)
    - Publicar no PubSub apenas quando o status do node MUDA
  """
  use GenServer
  require Logger

  alias Phoenix.PubSub
  alias WCore.Telemetry.Cache

  @table :w_core_telemetry_cache
  @pubsub WCore.PubSub
  @topic "telemetry:nodes"

  # --- API pública ---

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Processa um evento de heartbeat de um sensor."
  def ingest(node_id, status, payload) do
    GenServer.cast(__MODULE__, {:ingest, node_id, status, payload})
  end

  @doc "Retorna o estado atual de um node direto do ETS."
  def get_node_state(node_id) do
    Cache.get(node_id)
  end

  @doc "Retorna todos os estados do ETS."
  def all_nodes do
    Cache.all()
  end

  # --- Callbacks GenServer ---

  @impl true
  def init(_) do
    Logger.info("[TelemetryServer] Iniciando e criando tabela ETS #{@table}")
    # :set     → uma entrada por node_id (chave única)
    # :public  → LiveView pode ler diretamente sem passar pelo GenServer
    # :named_table → acessível por nome em qualquer processo
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:ingest, node_id, status, payload}, state) do
    previous = Cache.get(node_id)
    timestamp = DateTime.utc_now()

    # Atualiza o contador atomicamente — sem substituir o registro inteiro
    case previous do
      nil ->
        :ets.insert(@table, {node_id, status, 1, payload, timestamp})
        broadcast_change(node_id, nil, status)

      {^node_id, prev_status, _count, _payload, _ts} ->
        :ets.update_element(@table, node_id, [
          {2, status},
          {4, payload},
          {5, timestamp}
        ])
        # update_counter é atômico — incrementa sem risco de race condition
        :ets.update_counter(@table, node_id, {3, 1})

        # Update de status para gerar alertas imediatos e falhas relâmpago!
        # Agora o dashboard já consulta os contadores a 10FPS. Não precisamos afogar a rede!
        if prev_status != status do
          broadcast_change(node_id, prev_status, status)
        end
    end

    {:noreply, state}
  end

  # --- Privado ---

  defp broadcast_change(node_id, prev_status, new_status) do
    PubSub.broadcast(@pubsub, @topic, {
      :node_status_changed,
      %{node_id: node_id, prev_status: prev_status, status: new_status}
    })
  end
end
