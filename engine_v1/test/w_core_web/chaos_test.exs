defmodule WCore.ChaosTest do
  @moduledoc """
  Teste de resiliência: injeta 10.000 eventos concorrentes.
  """
  use WCore.TelemetryCase, async: false

  alias WCore.Telemetry
  alias WCore.Telemetry.{TelemetryServer, WriteWorker, Cache}

  @node_count 10
  @events_per_node 1_000
  @total_events @node_count * @events_per_node

  setup do
    # Cria os nodes no banco antes do caos
    nodes =
      Enum.map(1..@node_count, fn i ->
        {:ok, node} = Telemetry.create_node(%{
          machine_identifier: "chaos-machine-#{i}",
          location: "Setor #{i}"
        })
        node
      end)

    %{nodes: nodes}
  end

  test "10.000 eventos concorrentes — sem perda, sem race condition", %{nodes: nodes} do
    # --- FASE 1: injetar eventos concorrentemente ---
    nodes
    |> Task.async_stream(
      fn node ->
        Enum.each(1..@events_per_node, fn j ->
          status = if rem(j, 10) == 0, do: "warning", else: "ok"
          TelemetryServer.ingest(node.id, status, ~s({"seq": #{j}}))
        end)
      end,
      max_concurrency: @node_count,
      timeout: 30_000
    )
    |> Stream.run()

    # Espera drenar a fila
    :sys.get_state(WCore.Telemetry.TelemetryServer)

    # --- FASE 2: verificar integridade do ETS ---
    all_records = Cache.all()
    assert length(all_records) == @node_count

    total_counted =
      all_records
      |> Enum.map(fn {_, _, count, _, _} -> count end)
      |> Enum.sum()

    assert total_counted == @total_events

    # --- FASE 3: verificar sincronização com SQLite ---
    {:ok, _synced} = WriteWorker.sync_now()

    # Verifica cada node no banco
    Enum.each(nodes, fn node ->
      metric = Telemetry.get_metric_by_node(node.id)
      assert metric != nil
      assert metric.total_events_processed == @events_per_node
    end)
  end
end
