defmodule WCore.Telemetry do
  @moduledoc """
  Contexto de domínio para sensores e métricas da Planta 42.
  Responsável apenas por I/O com o SQLite — o fluxo de eventos
  em tempo real passa pelo TelemetryServer (OTP), não por aqui.
  """
  import Ecto.Query
  alias WCore.Repo
  alias WCore.Telemetry.{Node, NodeMetric}

  def list_nodes, do: Repo.all(Node)

  def get_node!(id), do: Repo.get!(Node, id)

  def create_node(attrs) do
    %Node{}
    |> Node.changeset(attrs)
    |> Repo.insert()
  end

  def upsert_metric(attrs) do
    %NodeMetric{}
    |> NodeMetric.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:status, :total_events_processed, :last_payload, :last_seen_at, :updated_at]},
      conflict_target: :node_id
    )
  end

  def get_metric_by_node(node_id) do
    Repo.get_by(NodeMetric, node_id: node_id)
  end
end
