# Passo 2: O Coracao da Usina (Erlang OTP & ETS)

## Objetivo

Construir o sistema de ingestao de alta performance usando GenServer + ETS como camada
de dados quentes, com mecanismo Write-Behind para persistencia assincrona no SQLite.

---

## 2.1 Por Que ETS?

### O Problema
Cada maquina envia pulsos a cada 1-5 segundos. Com 100 maquinas e 3 sensores cada,
sao ~300 escritas/segundo. Gravar cada uma diretamente no SQLite:
- Cria contenao no WAL
- Aumenta latencia de resposta da API de ingestao
- Bloqueia leituras do LiveView Dashboard

### A Solucao: ETS como Buffer

```
Sensor -> GenServer (PulseServer) -> ETS (dados quentes)
                                        |
                                   WriteBehind (timer)
                                        |
                                     SQLite (dados frios)
```

O LiveView le do ETS (microsegundos), nunca do SQLite para dados recentes.
O SQLite serve apenas para historico e queries analiticas.

### Tipo de Tabela ETS: `ordered_set` com `write_concurrency`

```elixir
:ets.new(:pulses_hot, [
  :ordered_set,          # Ordenado por chave composta {machine_id, sensor, timestamp}
  :public,               # Leituras diretas do LiveView sem passar pelo GenServer
  :named_table,
  read_concurrency: true,  # Multiplos LiveViews lendo simultaneamente
  write_concurrency: true  # Multiplos PulseServers gravando (1 por maquina)
])
```

**Por que `ordered_set`?**
- Permite range queries eficientes: "todos os pulsos da maquina X nos ultimos 5 min"
- Chave composta `{machine_id, sensor, timestamp}` permite `select` por prefixo
- `set` simples nao permite range queries nativas

**Por que `public`?**
- LiveViews leem diretamente sem message passing
- Elimina o GenServer como gargalo de leitura
- Escritas sao serializadas pelo PulseServer (1 por maquina), sem risco de corrida

---

## 2.2 Arvore de Supervisao

```elixir
# lib/w_core/ingestion/supervisor.ex
defmodule WCore.Ingestion.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Inicializa a tabela ETS
      WCore.Ingestion.TableManager,
      # Registry para PulseServers dinamicos (1 por maquina)
      {Registry, keys: :unique, name: WCore.Ingestion.Registry},
      # DynamicSupervisor para PulseServers
      {DynamicSupervisor, name: WCore.Ingestion.PulseSupervisor, strategy: :one_for_one},
      # Processo de Write-Behind (flush periodico)
      WCore.Ingestion.WriteBehind
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

### Estrategia de Supervisao: `one_for_one`

**Justificativa:**
- Se um `PulseServer` de uma maquina crashar, as outras continuam operando
- Se o `WriteBehind` crashar, os dados no ETS sobrevivem (ETS pertence ao `TableManager`)
- Se o `TableManager` crashar, a tabela ETS e destruida, mas o `WriteBehind` tera
  feito flush dos dados recentes. O `TableManager` recria a tabela ao reiniciar.

**Por que nao `rest_for_one`?**
O `DynamicSupervisor` nao depende do `WriteBehind` e vice-versa. Derrubar um nao
invalida o outro.

---

## 2.3 TableManager (Dono da ETS)

```elixir
# lib/w_core/ingestion/table_manager.ex
defmodule WCore.Ingestion.TableManager do
  @moduledoc """
  Dono da tabela ETS :pulses_hot.
  Existe unicamente para garantir que a tabela sobreviva
  ao crash de PulseServers individuais.
  """
  use GenServer

  @table :pulses_hot
  @machine_status_table :machines_status

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def table_name, do: @table
  def status_table_name, do: @machine_status_table

  @impl true
  def init(_) do
    table = :ets.new(@table, [
      :ordered_set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    status_table = :ets.new(@machine_status_table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{table: table, status_table: status_table}}
  end
end
```

---

## 2.4 PulseServer (1 por Maquina)

```elixir
# lib/w_core/ingestion/pulse_server.ex
defmodule WCore.Ingestion.PulseServer do
  @moduledoc """
  GenServer responsavel por receber pulsos de UMA maquina.
  Grava no ETS e notifica via PubSub.
  """
  use GenServer

  alias WCore.Ingestion.TableManager

  @max_pulses_per_sensor 500  # Limite de pulsos quentes por sensor

  # --- API Publica ---

  def start_link(%{machine_id: machine_id} = args) do
    GenServer.start_link(__MODULE__, args,
      name: via_tuple(machine_id)
    )
  end

  def ingest(machine_id, pulse_data) do
    case ensure_started(machine_id) do
      {:ok, pid} -> GenServer.cast(pid, {:ingest, pulse_data})
      error -> error
    end
  end

  def get_recent(machine_id, sensor, limit \\ 50) do
    table = TableManager.table_name()
    # Match spec para range query eficiente
    match_prefix = {machine_id, sensor, :_}

    table
    |> :ets.match_object({match_prefix, :_})
    |> Enum.sort_by(fn {{_, _, ts}, _} -> ts end, {:desc, DateTime})
    |> Enum.take(limit)
    |> Enum.map(fn {{_, _, _ts}, data} -> data end)
  end

  # --- Callbacks ---

  @impl true
  def init(%{machine_id: machine_id}) do
    # Atualiza status da maquina para online
    :ets.insert(TableManager.status_table_name(),
      {machine_id, %{status: :online, last_seen: DateTime.utc_now()}}
    )

    # Broadcast do status
    Phoenix.PubSub.broadcast(WCore.PubSub,
      "machines:status",
      {:machine_status_changed, machine_id, :online}
    )

    {:ok, %{machine_id: machine_id, pulse_count: 0}}
  end

  @impl true
  def handle_cast({:ingest, pulse_data}, state) do
    now = DateTime.utc_now()
    table = TableManager.table_name()

    # Chave composta: {machine_id, sensor, timestamp}
    key = {state.machine_id, pulse_data.sensor, now}
    record = Map.merge(pulse_data, %{
      machine_id: state.machine_id,
      recorded_at: now
    })

    :ets.insert(table, {key, record})

    # Atualiza status com last_seen
    :ets.insert(TableManager.status_table_name(),
      {state.machine_id, %{status: :online, last_seen: now}}
    )

    # Broadcast para LiveView
    Phoenix.PubSub.broadcast(WCore.PubSub,
      "machines:#{state.machine_id}",
      {:new_pulse, state.machine_id, record}
    )

    # Evicao: remove pulsos antigos quando excede limite
    new_count = state.pulse_count + 1
    state =
      if rem(new_count, @max_pulses_per_sensor) == 0 do
        evict_old_pulses(table, state.machine_id, pulse_data.sensor)
        %{state | pulse_count: 0}
      else
        %{state | pulse_count: new_count}
      end

    {:noreply, state}
  end

  # --- Helpers ---

  defp via_tuple(machine_id) do
    {:via, Registry, {WCore.Ingestion.Registry, machine_id}}
  end

  defp ensure_started(machine_id) do
    case Registry.lookup(WCore.Ingestion.Registry, machine_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        DynamicSupervisor.start_child(
          WCore.Ingestion.PulseSupervisor,
          {__MODULE__, %{machine_id: machine_id}}
        )
        |> case do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          error -> error
        end
    end
  end

  defp evict_old_pulses(table, machine_id, sensor) do
    cutoff = DateTime.utc_now() |> DateTime.add(-3600, :second)

    # Usando select_delete para eficiencia
    match_spec = [
      {{{machine_id, sensor, :"$1"}, :_},
       [{:<, :"$1", {:const, cutoff}}],
       [true]}
    ]

    :ets.select_delete(table, match_spec)
  end
end
```

---

## 2.5 Write-Behind (Flush Periodico)

```elixir
# lib/w_core/ingestion/write_behind.ex
defmodule WCore.Ingestion.WriteBehind do
  @moduledoc """
  Processo que periodicamente faz flush dos dados quentes (ETS)
  para o armazenamento frio (SQLite).

  Estrategia: a cada intervalo, coleta todos os registros do ETS
  que ainda nao foram persistidos e faz insert_all no SQLite.
  """
  use GenServer

  alias WCore.Ingestion.TableManager
  alias WCore.Repo
  alias WCore.Telemetry.Pulse

  @flush_interval_ms 10_000  # 10 segundos
  @batch_size 1_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_flush()
    {:ok, %{last_flush_at: DateTime.utc_now()}}
  end

  @impl true
  def handle_info(:flush, state) do
    new_state = do_flush(state)
    schedule_flush()
    {:noreply, new_state}
  end

  # Flush manual para testes
  def flush_now do
    GenServer.call(__MODULE__, :flush_now)
  end

  @impl true
  def handle_call(:flush_now, _from, state) do
    new_state = do_flush(state)
    {:reply, :ok, new_state}
  end

  # --- Logica de Flush ---

  defp do_flush(state) do
    table = TableManager.table_name()
    cutoff = state.last_flush_at

    # Seleciona registros inseridos desde o ultimo flush
    records =
      :ets.tab2list(table)
      |> Enum.filter(fn {{_machine_id, _sensor, ts}, _data} ->
        DateTime.compare(ts, cutoff) == :gt
      end)
      |> Enum.map(fn {_key, data} ->
        %{
          value: data.value,
          unit: data.unit,
          sensor: data.sensor,
          machine_id: data.machine_id,
          recorded_at: data.recorded_at,
          inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
      end)

    # Insert em batches para nao sobrecarregar o SQLite
    records
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(fn batch ->
      Repo.insert_all(Pulse, batch,
        on_conflict: :nothing  # Idempotente: se ja existe, ignora
      )
    end)

    %{state | last_flush_at: DateTime.utc_now()}
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval_ms)
  end
end
```

---

## 2.6 Integracao na Application

```elixir
# lib/w_core/application.ex - adicionar na lista de children
children = [
  WCoreWeb.Telemetry,
  WCore.Repo,
  {DNSCluster, query: Application.get_env(:w_core, :dns_cluster_query) || :ignore},
  {Phoenix.PubSub, name: WCore.PubSub},
  # Sistema de Ingestao (ETS + GenServers)
  WCore.Ingestion.Supervisor,
  # Endpoint por ultimo
  WCoreWeb.Endpoint
]
```

---

## 2.7 API de Ingestao (Endpoint HTTP)

```elixir
# lib/w_core_web/controllers/pulse_controller.ex
defmodule WCoreWeb.PulseController do
  use WCoreWeb, :controller

  def create(conn, %{"machine_id" => machine_id, "pulses" => pulses}) do
    machine_id = String.to_integer(machine_id)

    Enum.each(pulses, fn pulse ->
      WCore.Ingestion.PulseServer.ingest(machine_id, %{
        value: pulse["value"],
        unit: pulse["unit"],
        sensor: pulse["sensor"]
      })
    end)

    json(conn, %{status: "ok", count: length(pulses)})
  end
end

# Em router.ex
scope "/api", WCoreWeb do
  pipe_through :api
  post "/machines/:machine_id/pulses", PulseController, :create
end
```

---

## 2.8 Fluxo Completo

```
1. POST /api/machines/42/pulses
   [{"sensor":"temp","value":72.5,"unit":"celsius"}]

2. PulseController.create/2
   -> PulseServer.ingest(42, %{sensor: "temp", value: 72.5, unit: "celsius"})

3. PulseServer (GenServer para maquina 42)
   -> :ets.insert(:pulses_hot, {{42, "temp", ~U[...]}, %{...}})
   -> PubSub.broadcast("machines:42", {:new_pulse, 42, %{...}})

4. WriteBehind (a cada 10s)
   -> Coleta novos registros do ETS
   -> Repo.insert_all(Pulse, batch)

5. LiveView Dashboard (subscrito em "machines:42")
   -> Recebe {:new_pulse, ...}
   -> Atualiza grafico em tempo real
```

---

## 2.9 Checklist de Entrega

- [ ] `WCore.Ingestion.Supervisor` na arvore de supervisao
- [ ] Tabela ETS `:pulses_hot` criada como `ordered_set` com `read/write_concurrency`
- [ ] `PulseServer` inicia dinamicamente via `DynamicSupervisor`
- [ ] `WriteBehind` faz flush a cada 10s para SQLite
- [ ] Endpoint `POST /api/machines/:id/pulses` funcional
- [ ] PubSub broadcast em `"machines:#{id}"` a cada pulso
- [ ] Evicao de dados antigos (>1h) no ETS
- [ ] Crash de um PulseServer nao afeta outros
- [ ] `mix precommit` passa

---

## Defesa das Decisoes

| Decisao | Alternativa Rejeitada | Motivo |
|---------|----------------------|--------|
| ETS `ordered_set` | `set` | Range queries por timestamp sao essenciais |
| ETS `public` | `protected` | LiveViews leem direto, sem gargalo no GenServer |
| 1 GenServer/maquina | 1 GenServer global | Isolamento de falhas, sem contenao |
| Write-Behind 10s | Write-Through | SQLite nao aguenta 300 writes/s sustentado |
| `one_for_one` | `rest_for_one` | Componentes sao independentes |

**Proximo:** Passo 3 - A Sala de Controle (Design System e LiveView)
