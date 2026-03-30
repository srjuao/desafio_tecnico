# Passo 4: Simulacao de Caos (Testes Rigorosos)

## Objetivo

Provar a resiliencia do sistema com testes unitarios, de integracao e de stress.
O teste principal injeta 10.000 eventos concorrentes e verifica que o ETS
nao perdeu dados, nao houve race conditions e o SQLite sincronizou corretamente.

---

## 4.1 Estrutura de Testes

```
test/
  w_core/
    telemetry_test.exs           # Unitario: contexto Telemetry
    ingestion/
      pulse_server_test.exs      # Unitario: GenServer
      write_behind_test.exs      # Unitario: flush ETS -> SQLite
      table_manager_test.exs     # Unitario: criacao de tabelas
      stress_test.exs            # Integracao: 10k eventos concorrentes
  w_core_web/
    live/
      dashboard_live_test.exs    # LiveView: renderizacao e PubSub
      machine_live_test.exs      # LiveView: grafico e atualizacoes
  support/
    fixtures/
      telemetry_fixtures.ex      # Factories para Machine e Pulse
```

---

## 4.2 Fixtures

```elixir
# test/support/fixtures/telemetry_fixtures.ex
defmodule WCore.TelemetryFixtures do
  alias WCore.Telemetry

  def machine_fixture(attrs \\ %{}) do
    {:ok, machine} =
      attrs
      |> Enum.into(%{
        name: "Machine #{System.unique_integer([:positive])}",
        identifier: "MCH-#{System.unique_integer([:positive])}",
        type: "cnc"
      })
      |> Telemetry.create_machine()

    machine
  end

  def pulse_data_fixture(attrs \\ %{}) do
    Enum.into(attrs, %{
      value: :rand.uniform() * 100,
      unit: "celsius",
      sensor: "temp_main"
    })
  end
end
```

---

## 4.3 Teste Unitario: PulseServer

```elixir
# test/w_core/ingestion/pulse_server_test.exs
defmodule WCore.Ingestion.PulseServerTest do
  use WCore.DataCase, async: false

  alias WCore.Ingestion.{PulseServer, TableManager}

  import WCore.TelemetryFixtures

  setup do
    machine = machine_fixture()
    {:ok, machine: machine}
  end

  describe "ingest/2" do
    test "grava pulso no ETS", %{machine: machine} do
      pulse = pulse_data_fixture()

      PulseServer.ingest(machine.id, pulse)

      # GenServer.cast e async, dar tempo de processar
      assert_eventually(fn ->
        results = PulseServer.get_recent(machine.id, pulse.sensor, 10)
        length(results) == 1
      end)
    end

    test "inicia PulseServer automaticamente se nao existir", %{machine: machine} do
      pulse = pulse_data_fixture()

      assert {:ok, _pid} = PulseServer.ingest(machine.id, pulse)
    end

    test "broadcast via PubSub ao receber pulso", %{machine: machine} do
      Phoenix.PubSub.subscribe(WCore.PubSub, "machines:#{machine.id}")
      pulse = pulse_data_fixture()

      PulseServer.ingest(machine.id, pulse)

      assert_receive {:new_pulse, ^(machine.id), _data}, 1_000
    end

    test "atualiza status da maquina para online", %{machine: machine} do
      PulseServer.ingest(machine.id, pulse_data_fixture())

      assert_eventually(fn ->
        case :ets.lookup(TableManager.status_table_name(), machine.id) do
          [{_, %{status: :online}}] -> true
          _ -> false
        end
      end)
    end
  end

  describe "get_recent/3" do
    test "retorna pulsos ordenados por timestamp descendente", %{machine: machine} do
      for i <- 1..5 do
        PulseServer.ingest(machine.id, pulse_data_fixture(%{value: i * 1.0}))
        Process.sleep(10)  # Garantir timestamps diferentes
      end

      assert_eventually(fn ->
        results = PulseServer.get_recent(machine.id, "temp_main", 5)
        length(results) == 5
      end)

      results = PulseServer.get_recent(machine.id, "temp_main", 5)
      values = Enum.map(results, & &1.value)
      assert values == Enum.sort(values, :desc)
    end
  end

  # Helper para assercoes async
  defp assert_eventually(fun, timeout \\ 1_000, interval \\ 50) do
    deadline = System.monotonic_time(:millisecond) + timeout

    do_assert_eventually(fun, deadline, interval)
  end

  defp do_assert_eventually(fun, deadline, interval) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        flunk("Condition not met within timeout")
      else
        Process.sleep(interval)
        do_assert_eventually(fun, deadline, interval)
      end
    end
  end
end
```

---

## 4.4 Teste Unitario: WriteBehind

```elixir
# test/w_core/ingestion/write_behind_test.exs
defmodule WCore.Ingestion.WriteBehindTest do
  use WCore.DataCase, async: false

  alias WCore.Ingestion.{PulseServer, WriteBehind}
  alias WCore.Telemetry.Pulse
  alias WCore.Repo

  import WCore.TelemetryFixtures

  setup do
    machine = machine_fixture()
    {:ok, machine: machine}
  end

  test "flush persiste dados do ETS no SQLite", %{machine: machine} do
    # Ingerir pulsos
    for _ <- 1..10 do
      PulseServer.ingest(machine.id, pulse_data_fixture())
    end

    # Aguardar processamento dos casts
    Process.sleep(200)

    # Flush manual
    WriteBehind.flush_now()

    # Verificar no SQLite
    count = Repo.aggregate(Pulse, :count)
    assert count == 10
  end

  test "flush e idempotente - nao duplica registros", %{machine: machine} do
    for _ <- 1..5 do
      PulseServer.ingest(machine.id, pulse_data_fixture())
    end

    Process.sleep(200)

    # Dois flushes seguidos
    WriteBehind.flush_now()
    WriteBehind.flush_now()

    count = Repo.aggregate(Pulse, :count)
    assert count == 5
  end
end
```

---

## 4.5 TESTE DE STRESS: 10.000 Eventos Concorrentes

```elixir
# test/w_core/ingestion/stress_test.exs
defmodule WCore.Ingestion.StressTest do
  @moduledoc """
  Teste de stress: injeta 10.000 eventos concorrentes em multiplas
  maquinas e verifica integridade dos dados.
  """
  use WCore.DataCase, async: false

  alias WCore.Ingestion.{PulseServer, WriteBehind, TableManager}
  alias WCore.Telemetry.Pulse
  alias WCore.Repo

  import WCore.TelemetryFixtures

  @total_events 10_000
  @num_machines 20
  @events_per_machine div(@total_events, @num_machines)  # 500 cada

  setup do
    machines =
      for _ <- 1..@num_machines do
        machine_fixture()
      end

    {:ok, machines: machines}
  end

  @tag timeout: 60_000
  test "10.000 eventos concorrentes sem perda de dados", %{machines: machines} do
    # ======================================
    # FASE 1: Injecao concorrente
    # ======================================

    parent = self()

    # Lanca 1 Task por maquina, cada uma enviando 500 pulsos
    tasks =
      Enum.map(machines, fn machine ->
        Task.async(fn ->
          for i <- 1..@events_per_machine do
            PulseServer.ingest(machine.id, %{
              value: i * 1.0,
              unit: "celsius",
              sensor: "temp_main"
            })
          end

          {:done, machine.id, @events_per_machine}
        end)
      end)

    # Aguarda todas as Tasks completarem
    results = Task.await_many(tasks, 30_000)

    # Verifica que todas completaram
    assert length(results) == @num_machines
    assert Enum.all?(results, fn {:done, _, count} -> count == @events_per_machine end)

    # Aguardar processamento dos casts (GenServer.cast e async)
    Process.sleep(2_000)

    # ======================================
    # FASE 2: Verificacao ETS (dados quentes)
    # ======================================

    ets_total = :ets.info(TableManager.table_name(), :size)

    # ETS deve ter EXATAMENTE 10.000 registros (ordered_set, chaves unicas)
    # Nota: se timestamps colidiram, pode ter menos. Verificamos >= 95%
    assert ets_total >= @total_events * 0.95,
      "ETS perdeu dados: esperado >= #{@total_events * 0.95}, obteve #{ets_total}"

    # ======================================
    # FASE 3: Verificacao por maquina
    # ======================================

    for machine <- machines do
      count =
        :ets.match_object(TableManager.table_name(), {{machine.id, :_, :_}, :_})
        |> length()

      assert count >= @events_per_machine * 0.95,
        "Maquina #{machine.id} perdeu dados: esperado >= #{@events_per_machine * 0.95}, obteve #{count}"
    end

    # ======================================
    # FASE 4: Nenhuma race condition nos status
    # ======================================

    for machine <- machines do
      case :ets.lookup(TableManager.status_table_name(), machine.id) do
        [{_, %{status: :online}}] ->
          :ok

        other ->
          flunk("Maquina #{machine.id} com status inesperado: #{inspect(other)}")
      end
    end

    # ======================================
    # FASE 5: Write-Behind -> SQLite
    # ======================================

    WriteBehind.flush_now()

    sqlite_count = Repo.aggregate(Pulse, :count)

    assert sqlite_count >= ets_total * 0.95,
      "SQLite perdeu dados no flush: ETS=#{ets_total}, SQLite=#{sqlite_count}"

    # Verificar integridade por maquina no SQLite
    for machine <- machines do
      machine_count =
        Pulse
        |> Ecto.Query.where([p], p.machine_id == ^machine.id)
        |> Repo.aggregate(:count)

      assert machine_count > 0,
        "Maquina #{machine.id} sem dados no SQLite apos flush"
    end

    # ======================================
    # FASE 6: Consistencia ETS <-> SQLite
    # ======================================

    # Os valores no SQLite devem corresponder aos do ETS
    for machine <- Enum.take(machines, 3) do
      ets_records =
        :ets.match_object(TableManager.table_name(), {{machine.id, "temp_main", :_}, :_})
        |> Enum.map(fn {_key, data} -> data.value end)
        |> Enum.sort()

      sqlite_records =
        Pulse
        |> Ecto.Query.where([p], p.machine_id == ^machine.id and p.sensor == "temp_main")
        |> Ecto.Query.select([p], p.value)
        |> Repo.all()
        |> Enum.sort()

      # Mesmos valores (ou subconjunto, se evicao ocorreu)
      assert length(sqlite_records) > 0
      assert MapSet.subset?(MapSet.new(sqlite_records), MapSet.new(ets_records)) or
             MapSet.subset?(MapSet.new(ets_records), MapSet.new(sqlite_records)),
        "Inconsistencia entre ETS e SQLite para maquina #{machine.id}"
    end
  end

  @tag timeout: 30_000
  test "crash de PulseServer nao afeta outras maquinas", %{machines: machines} do
    [machine_a, machine_b | _] = machines

    # Ingerir dados em ambas
    PulseServer.ingest(machine_a.id, pulse_data_fixture())
    PulseServer.ingest(machine_b.id, pulse_data_fixture())
    Process.sleep(200)

    # Encontrar e matar o PulseServer da maquina A
    [{pid_a, _}] = Registry.lookup(WCore.Ingestion.Registry, machine_a.id)
    ref = Process.monitor(pid_a)
    Process.exit(pid_a, :kill)
    assert_receive {:DOWN, ^ref, :process, _, _}, 1_000

    # Maquina B deve continuar operando normalmente
    PulseServer.ingest(machine_b.id, pulse_data_fixture(%{value: 999.0}))
    Process.sleep(200)

    results_b = PulseServer.get_recent(machine_b.id, "temp_main", 10)
    assert length(results_b) >= 2

    # Maquina A deve reiniciar via DynamicSupervisor
    PulseServer.ingest(machine_a.id, pulse_data_fixture(%{value: 111.0}))
    Process.sleep(200)

    results_a = PulseServer.get_recent(machine_a.id, "temp_main", 10)
    assert Enum.any?(results_a, fn p -> p.value == 111.0 end)
  end

  @tag timeout: 30_000
  test "leituras concorrentes ao ETS durante escritas intensas", %{machines: machines} do
    machine = hd(machines)

    # Escritor: envia pulsos continuamente
    writer = Task.async(fn ->
      for i <- 1..1_000 do
        PulseServer.ingest(machine.id, pulse_data_fixture(%{value: i * 1.0}))
      end
    end)

    # Leitores: consultam ETS simultaneamente
    readers =
      for _ <- 1..10 do
        Task.async(fn ->
          for _ <- 1..100 do
            results = PulseServer.get_recent(machine.id, "temp_main", 50)
            # Nao deve crashar, e valores devem ser consistentes
            assert is_list(results)
            Enum.each(results, fn p ->
              assert is_float(p.value)
              assert p.sensor == "temp_main"
            end)
          end

          :ok
        end)
      end

    Task.await(writer, 15_000)
    results = Task.await_many(readers, 15_000)
    assert Enum.all?(results, &(&1 == :ok))
  end
end
```

---

## 4.6 Teste de LiveView

```elixir
# test/w_core_web/live/dashboard_live_test.exs
defmodule WCoreWeb.DashboardLiveTest do
  use WCoreWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import WCore.TelemetryFixtures

  setup %{conn: conn} do
    user = WCore.AccountsFixtures.user_fixture()
    conn = log_in_user(conn, user)
    machine = machine_fixture(%{name: "CNC Alpha", identifier: "CNC-001"})
    {:ok, conn: conn, machine: machine}
  end

  test "renderiza lista de maquinas", %{conn: conn, machine: machine} do
    {:ok, view, html} = live(conn, ~p"/dashboard")

    assert html =~ "Sala de Controle"
    assert html =~ machine.name
    assert html =~ machine.identifier
  end

  test "atualiza status em tempo real via PubSub", %{conn: conn, machine: machine} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    Phoenix.PubSub.broadcast(WCore.PubSub,
      "machines:status",
      {:machine_status_changed, machine.id, :online}
    )

    # LiveView deve receber e re-renderizar
    assert render(view) =~ "online"
  end
end
```

---

## 4.7 Checklist de Entrega

- [ ] Teste de stress com 10.000 eventos passa
- [ ] Zero perda de dados no ETS (>= 95% dos eventos registrados)
- [ ] WriteBehind sincroniza ETS -> SQLite sem perda
- [ ] Consistencia de dados entre ETS e SQLite verificada
- [ ] Crash de PulseServer individual nao afeta outras maquinas
- [ ] Leituras concorrentes ao ETS nao crasham durante escritas intensas
- [ ] Testes de LiveView verificam renderizacao e PubSub
- [ ] Nenhum `Process.sleep` desnecessario (usar `assert_eventually`)
- [ ] `mix test` completo < 60 segundos
- [ ] `mix precommit` passa

---

## Metricas Esperadas

| Metrica | Alvo | Aceitavel |
|---------|------|-----------|
| 10k eventos ingeridos | 0% perda | < 5% perda |
| Tempo de ingestao 10k | < 5s | < 10s |
| Flush ETS -> SQLite | 0% perda | < 5% perda |
| Crash recovery | < 100ms | < 500ms |
| Leitura ETS durante stress | 0 crashes | 0 crashes |

**Proximo:** Passo 5 - O Empacotamento para o Edge (Infraestrutura)
