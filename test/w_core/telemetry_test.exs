defmodule WCore.TelemetryTest do
  use WCore.DataCase

  alias WCore.Telemetry

  import WCore.TelemetryFixtures

  describe "machines" do
    test "list_machines/0 returns all machines" do
      machine = machine_fixture()
      assert Telemetry.list_machines() == [machine]
    end

    test "get_machine!/1 returns the machine with given id" do
      machine = machine_fixture()
      assert Telemetry.get_machine!(machine.id) == machine
    end

    test "create_machine/1 with valid data creates a machine" do
      attrs = %{name: "CNC Alpha", identifier: "CNC-001", type: "cnc"}
      assert {:ok, machine} = Telemetry.create_machine(attrs)
      assert machine.name == "CNC Alpha"
      assert machine.identifier == "CNC-001"
      assert machine.status == "offline"
    end

    test "create_machine/1 with duplicate identifier returns error" do
      machine = machine_fixture()
      attrs = %{name: "Other", identifier: machine.identifier, type: "press"}
      assert {:error, changeset} = Telemetry.create_machine(attrs)
      assert %{identifier: _} = errors_on(changeset)
    end

    test "update_machine_status/2 changes the status" do
      machine = machine_fixture()
      assert {:ok, updated} = Telemetry.update_machine_status(machine, "online")
      assert updated.status == "online"
    end

    test "get_machine_by_identifier/1 finds by identifier" do
      machine = machine_fixture()
      assert Telemetry.get_machine_by_identifier(machine.identifier) == machine
    end
  end

  describe "pulses" do
    test "create_pulse/1 with valid data creates a pulse" do
      machine = machine_fixture()

      attrs = %{
        value: 72.5,
        unit: "celsius",
        sensor: "temp_main",
        recorded_at: DateTime.utc_now() |> DateTime.truncate(:second),
        machine_id: machine.id
      }

      assert {:ok, pulse} = Telemetry.create_pulse(attrs)
      assert pulse.value == 72.5
      assert pulse.sensor == "temp_main"
    end

    test "recent_pulses/3 returns pulses ordered by recorded_at desc" do
      machine = machine_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for i <- 1..5 do
        Telemetry.create_pulse(%{
          value: i * 10.0,
          unit: "celsius",
          sensor: "temp_main",
          recorded_at: DateTime.add(now, i, :second),
          machine_id: machine.id
        })
      end

      pulses = Telemetry.recent_pulses(machine.id, "temp_main", 3)
      assert length(pulses) == 3
      values = Enum.map(pulses, & &1.value)
      assert values == [50.0, 40.0, 30.0]
    end
  end
end
