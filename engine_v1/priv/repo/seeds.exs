# Script para popular o banco de dados.
alias WCore.Repo
alias WCore.Telemetry.Node

# Criar sensores industriais se não existirem
nodes_data = [
  %{machine_identifier: "GERADOR-X1", location: "Setor Norte"},
  %{machine_identifier: "CALDEIRA-B4", location: "Setor Leste"},
  %{machine_identifier: "TURBINA-09", location: "Subsolo"},
  %{machine_identifier: "COMPRESSOR-T1", location: "Setor Sul"},
  %{machine_identifier: "ESTEIRA-M12", location: "Galpão Principal"}
]

for data <- nodes_data do
  case Repo.get_by(Node, machine_identifier: data.machine_identifier) do
    nil -> Repo.insert!(struct(Node, data))
    _node -> :ok
  end
end

IO.puts "✅ Banco semeado com sensores industriais!"
