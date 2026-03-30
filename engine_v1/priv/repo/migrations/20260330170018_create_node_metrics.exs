defmodule WCore.Repo.Migrations.CreateNodeMetrics do
  use Ecto.Migration

  def change do
    create table(:node_metrics) do
      add :node_id, references(:nodes, on_delete: :delete_all), null: false
      add :status, :string, default: "unknown", null: false
      add :total_events_processed, :integer, default: 0
      add :last_payload, :string
      add :last_seen_at, :utc_datetime

      timestamps()
    end

    create unique_index(:node_metrics, [:node_id])
    create index(:node_metrics, [:status])
  end
end
