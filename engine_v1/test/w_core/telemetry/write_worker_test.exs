defmodule WCore.Telemetry.WriteWorkerTest do
  use WCore.TelemetryCase, async: false

  alias WCore.Telemetry.{TelemetryServer, WriteWorker}
  alias WCore.Telemetry

  setup do
    # Cria um node real no banco para o upsert funcionar
    {:ok, node} = Telemetry.create_node(%{
      machine_identifier: "worker-test-machine",
      location: "Setor A"
    })

    %{node: node}
  end

  describe "sync_now/0" do
    test "persiste estado do ETS no SQLite", %{node: node} do
      TelemetryServer.ingest(node.id, "ok", ~s({"temp": 72}))
      :timer.sleep(100)

      {:ok, count} = WriteWorker.sync_now()
      assert count >= 1

      metric = Telemetry.get_metric_by_node(node.id)
      assert metric != nil
      assert metric.status == "ok"
      assert metric.total_events_processed == 1
    end

    test "upsert — atualiza métrica existente sem duplicar", %{node: node} do
      TelemetryServer.ingest(node.id, "ok", "{}")
      :timer.sleep(100)
      WriteWorker.sync_now()

      TelemetryServer.ingest(node.id, "critical", ~s({"temp": 105}))
      :timer.sleep(100)
      WriteWorker.sync_now()

      # Deve haver apenas UMA linha de métrica para este node
      import Ecto.Query
      metrics = WCore.Repo.all(
        from m in WCore.Telemetry.NodeMetric,
        where: m.node_id == ^node.id
      )
      assert length(metrics) == 1
      assert hd(metrics).status == "critical"
    end
  end
end
