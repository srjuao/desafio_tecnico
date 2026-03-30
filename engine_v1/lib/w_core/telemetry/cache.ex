defmodule WCore.Telemetry.Cache do
  @moduledoc """
  Interface de leitura da tabela ETS :w_core_telemetry_cache.

  Centraliza os acessos ao ETS para que o resto do sistema
  não precise conhecer a estrutura interna da tupla.
  """

  @table :w_core_telemetry_cache

  def get(node_id) do
    case :ets.lookup(@table, node_id) do
      [record] -> record
      []       -> nil
    end
  end

  def all do
    :ets.tab2list(@table)
  end

  def to_map({node_id, status, event_count, last_payload, timestamp}) do
    %{
      node_id: node_id,
      status: status,
      event_count: event_count,
      last_payload: last_payload,
      timestamp: timestamp
    }
  end
end
