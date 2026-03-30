defmodule WCore.TelemetryFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `WCore.Telemetry` context.
  """

  def machine_fixture(attrs \\ %{}) do
    {:ok, machine} =
      attrs
      |> Enum.into(%{
        name: "Machine #{System.unique_integer([:positive])}",
        identifier: "MCH-#{System.unique_integer([:positive])}",
        type: "cnc"
      })
      |> WCore.Telemetry.create_machine()

    machine
  end

  def pulse_fixture(attrs \\ %{}) do
    machine = attrs[:machine] || machine_fixture()

    {:ok, pulse} =
      attrs
      |> Map.drop([:machine])
      |> Enum.into(%{
        value: :rand.uniform() * 100,
        unit: "celsius",
        sensor: "temp_main",
        recorded_at: DateTime.utc_now() |> DateTime.truncate(:second),
        machine_id: machine.id
      })
      |> WCore.Telemetry.create_pulse()

    pulse
  end
end
