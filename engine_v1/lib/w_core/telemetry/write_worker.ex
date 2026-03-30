defmodule WCore.Telemetry.WriteWorker do
  @moduledoc """
  Worker responsável por persistir o estado do ETS no SQLite.

  Estratégia Write-Behind:
    A cada @sync_interval ms, varre toda a tabela ETS e executa
    um upsert em lote no SQLite.
  """
  use GenServer
  require Logger

  alias WCore.Telemetry
  alias WCore.Telemetry.Cache

  # Sincroniza com o SQLite a cada 5 segundos
  @sync_interval 5_000

  # --- API pública ---

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Força uma sincronização imediata (útil em testes)."
  def sync_now do
    GenServer.call(__MODULE__, :sync_now)
  end

  # --- Callbacks GenServer ---

  @impl true
  def init(_) do
    Logger.info("[WriteWorker] Iniciando — sync a cada #{@sync_interval}ms")
    schedule_sync()
    {:ok, %{last_sync: nil, total_synced: 0}}
  end

  @impl true
  def handle_info(:sync, state) do
    count = do_sync()
    schedule_sync()
    {:noreply, %{state | last_sync: DateTime.utc_now(), total_synced: state.total_synced + count}}
  end

  @impl true
  def handle_call(:sync_now, _from, state) do
    count = do_sync()
    {:reply, {:ok, count}, %{state | last_sync: DateTime.utc_now(), total_synced: state.total_synced + count}}
  end

  # --- Privado ---

  defp schedule_sync do
    Process.send_after(self(), :sync, @sync_interval)
  end

  defp do_sync do
    records = Cache.all()

    Enum.each(records, fn {node_id, status, event_count, last_payload, timestamp} ->
      # OBS: O TelemetryServer usa node_id do ETS (que pode ser a machine_identifier ou o ID do banco).
      # Na estrutura do usuário, o upsert_metric usa node_id (FK para a tabela nodes).
      # Para este exemplo, assumimos que o node_id passado para o ingest é o ID numérico do banco.
      
      Telemetry.upsert_metric(%{
        node_id: node_id,
        status: status,
        total_events_processed: event_count,
        last_payload: last_payload,
        last_seen_at: timestamp
      })
    end)

    count = length(records)
    if count > 0, do: Logger.debug("[WriteWorker] Sincronizou #{count} nodes com o SQLite")
    count
  end
end
