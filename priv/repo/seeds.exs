# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs

alias WCore.Telemetry

# Seed machines
machines = [
  %{name: "CNC Alpha", identifier: "CNC-001", type: "cnc"},
  %{name: "Prensa Hidraulica", identifier: "PRESS-001", type: "press"},
  %{name: "Esteira Principal", identifier: "CONV-001", type: "conveyor"},
  %{name: "CNC Beta", identifier: "CNC-002", type: "cnc"},
  %{name: "Compressor Central", identifier: "COMP-001", type: "compressor"}
]

for attrs <- machines do
  case Telemetry.get_machine_by_identifier(attrs.identifier) do
    nil -> Telemetry.create_machine(attrs)
    _exists -> :ok
  end
end

IO.puts("Seeds loaded: #{length(machines)} machines")
