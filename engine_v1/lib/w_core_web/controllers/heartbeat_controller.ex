defmodule WCoreWeb.HeartbeatController do
  @moduledoc """
  Endpoint que os sensores da Planta 42 chamam para enviar heartbeats.
  Repassa imediatamente para o TelemetryServer e retorna 200.
  Não toca no banco — isso é papel do WriteWorker.
  """
  use WCoreWeb, :controller

  alias WCore.Telemetry.TelemetryServer

  def create(conn, %{"node_id" => node_id, "status" => status, "payload" => payload}) do
    TelemetryServer.ingest(node_id, status, payload)
    send_resp(conn, 200, "ok")
  end
end
