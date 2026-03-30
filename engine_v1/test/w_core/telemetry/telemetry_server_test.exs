defmodule WCore.Telemetry.TelemetryServerTest do
  use WCore.TelemetryCase, async: false

  alias WCore.Telemetry.{TelemetryServer, Cache}

  describe "ingest/3 — inserção inicial" do
    test "insere novo node no ETS" do
      TelemetryServer.ingest("machine-01", "ok", ~s({"temp": 70}))

      # cast é assíncrono — aguarda o GenServer processar
      :timer.sleep(100)

      assert {id, status, count, _payload, _ts} = Cache.get("machine-01")
      assert id == "machine-01"
      assert status == "ok"
      assert count == 1
    end

    test "inicializa event_count em 1 para novo node" do
      TelemetryServer.ingest("machine-02", "warning", "{}")
      :timer.sleep(100)

      {_, _, count, _, _} = Cache.get("machine-02")
      assert count == 1
    end
  end

  describe "ingest/3 — atualização de node existente" do
    test "incrementa event_count a cada evento" do
      TelemetryServer.ingest("machine-03", "ok", "{}")
      TelemetryServer.ingest("machine-03", "ok", "{}")
      TelemetryServer.ingest("machine-03", "ok", "{}")
      :timer.sleep(100)

      {_, _, count, _, _} = Cache.get("machine-03")
      assert count == 3
    end

    test "atualiza status corretamente" do
      TelemetryServer.ingest("machine-04", "ok", "{}")
      :timer.sleep(100)
      TelemetryServer.ingest("machine-04", "critical", ~s({"temp": 120}))
      :timer.sleep(100)

      {_, status, _, payload, _} = Cache.get("machine-04")
      assert status == "critical"
      assert payload == ~s({"temp": 120})
    end
  end

  describe "PubSub — broadcast condicional" do
    setup do
      Phoenix.PubSub.subscribe(WCore.PubSub, "telemetry:nodes")
      :ok
    end

    test "publica quando status muda de ok para critical" do
      TelemetryServer.ingest("machine-06", "ok", "{}")
      :timer.sleep(100)
      TelemetryServer.ingest("machine-06", "critical", "{}")

      assert_receive {:node_status_changed, %{node_id: "machine-06",
        prev_status: "ok", status: "critical"}}, 1000
    end

    test "NÃO publica quando status permanece igual" do
      TelemetryServer.ingest("machine-07", "ok", "{}")
      assert_receive {:node_status_changed, %{node_id: "machine-07"}}, 500

      TelemetryServer.ingest("machine-07", "ok", ~s({"temp": 71}))
      :timer.sleep(100)

      refute_receive {:node_status_changed, %{node_id: "machine-07"}}, 200
    end
  end
end
