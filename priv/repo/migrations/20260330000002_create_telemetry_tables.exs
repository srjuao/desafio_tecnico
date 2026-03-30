defmodule WCore.Repo.Migrations.CreateTelemetryTables do
  use Ecto.Migration

  def change do
    create table(:machines) do
      add :name, :string, null: false
      add :identifier, :string, null: false
      add :type, :string, null: false
      add :status, :string, default: "offline", null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:machines, [:identifier])

    create table(:pulses) do
      add :value, :float, null: false
      add :unit, :string, null: false
      add :sensor, :string, null: false
      add :recorded_at, :utc_datetime, null: false
      add :machine_id, references(:machines, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:pulses, [:machine_id])
    create index(:pulses, [:recorded_at])
    create index(:pulses, [:machine_id, :sensor, :recorded_at])
  end
end
