defmodule WCore.Telemetry do
  @moduledoc """
  The Telemetry context.
  Public interface for operations with machines and sensor pulses.
  """
  import Ecto.Query

  alias WCore.Repo
  alias WCore.Telemetry.{Machine, Pulse}

  # --- Machines ---

  def list_machines do
    Repo.all(Machine)
  end

  def get_machine!(id), do: Repo.get!(Machine, id)

  def get_machine_by_identifier(identifier) do
    Repo.get_by(Machine, identifier: identifier)
  end

  def create_machine(attrs) do
    %Machine{}
    |> Machine.changeset(attrs)
    |> Repo.insert()
  end

  def update_machine(%Machine{} = machine, attrs) do
    machine
    |> Machine.changeset(attrs)
    |> Repo.update()
  end

  def update_machine_status(%Machine{} = machine, status) do
    machine
    |> Machine.changeset(%{status: status})
    |> Repo.update()
  end

  def delete_machine(%Machine{} = machine) do
    Repo.delete(machine)
  end

  def change_machine(%Machine{} = machine, attrs \\ %{}) do
    Machine.changeset(machine, attrs)
  end

  # --- Pulses ---

  def create_pulse(attrs) do
    %Pulse{}
    |> Pulse.changeset(attrs)
    |> Repo.insert()
  end

  def insert_pulses_batch(pulses_attrs) when is_list(pulses_attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.map(pulses_attrs, fn attrs ->
        attrs
        |> Map.put_new(:inserted_at, now)
        |> Map.put_new(:updated_at, now)
      end)

    Repo.insert_all(Pulse, entries)
  end

  def recent_pulses(machine_id, sensor, limit \\ 100) do
    Pulse
    |> where([p], p.machine_id == ^machine_id and p.sensor == ^sensor)
    |> order_by([p], desc: p.recorded_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def pulse_count(machine_id) do
    Pulse
    |> where([p], p.machine_id == ^machine_id)
    |> Repo.aggregate(:count)
  end
end
