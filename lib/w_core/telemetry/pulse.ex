defmodule WCore.Telemetry.Pulse do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pulses" do
    field :value, :float
    field :unit, :string
    field :sensor, :string
    field :recorded_at, :utc_datetime

    belongs_to :machine, WCore.Telemetry.Machine
    timestamps(type: :utc_datetime)
  end

  def changeset(pulse, attrs) do
    pulse
    |> cast(attrs, [:value, :unit, :sensor, :recorded_at, :machine_id])
    |> validate_required([:value, :unit, :sensor, :machine_id])
    |> foreign_key_constraint(:machine_id)
  end
end
