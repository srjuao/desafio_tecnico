defmodule WCore.Telemetry.Machine do
  use Ecto.Schema
  import Ecto.Changeset

  schema "machines" do
    field :name, :string
    field :identifier, :string
    field :type, :string
    field :status, :string, default: "offline"
    field :metadata, :map, default: %{}

    has_many :pulses, WCore.Telemetry.Pulse
    timestamps(type: :utc_datetime)
  end

  def changeset(machine, attrs) do
    machine
    |> cast(attrs, [:name, :identifier, :type, :status, :metadata])
    |> validate_required([:name, :identifier, :type])
    |> unique_constraint(:identifier)
    |> validate_inclusion(:status, ~w(online offline alert))
  end
end
