defmodule WCore.Telemetry.Node do
  @moduledoc """
  Representa um sensor físico cadastrado na Planta 42.
  É um registro estático — criado na configuração da planta,
  não a cada evento recebido.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "nodes" do
    field :machine_identifier, :string
    field :location, :string

    has_one :metric, WCore.Telemetry.NodeMetric
    timestamps()
  end

  def changeset(node, attrs) do
    node
    |> cast(attrs, [:machine_identifier, :location])
    |> validate_required([:machine_identifier, :location])
    |> unique_constraint(:machine_identifier)
  end
end
