defmodule WCore.Telemetry.NodeMetric do
  @moduledoc """
  Consolidado do último estado conhecido de um sensor.
  Atualizado de forma assíncrona pelo WriteWorker via upsert em lote.
  NÃO é atualizado diretamente por cada evento — isso é papel do ETS.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "node_metrics" do
    field :status, :string, default: "unknown"
    field :total_events_processed, :integer, default: 0
    field :last_payload, :string
    field :last_seen_at, :utc_datetime

    belongs_to :node, WCore.Telemetry.Node
    timestamps()
  end

  def changeset(metric, attrs) do
    metric
    |> cast(attrs, [:status, :total_events_processed, :last_payload, :last_seen_at, :node_id])
    |> validate_required([:node_id, :status])
    |> validate_inclusion(:status, ["ok", "warning", "critical", "unknown"])
    |> foreign_key_constraint(:node_id)
  end
end
