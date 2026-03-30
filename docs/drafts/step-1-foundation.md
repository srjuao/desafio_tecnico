# Passo 1: O Perimetro de Seguranca (Fundacao e Autenticacao)

## Objetivo

Estabelecer a fundacao solida do WCore: banco de dados SQLite configurado com schemas,
autenticacao completa via `mix phx.gen.auth`, e separacao clara entre o dominio de
Telemetria (dados de maquinas) e a camada web.

---

## 1.1 Banco de Dados SQLite

### Estado Atual
- Repo configurado em `lib/w_core/repo.ex` com adapter `Ecto.Adapters.SQLite3`
- Nenhuma migration existe ainda
- Config em `config/dev.exs` aponta para `priv/repo/w_core_dev.db`

### Acoes

```bash
# Garantir que o banco esta funcional
mix ecto.create
mix ecto.migrate
```

### Otimizacoes SQLite para Telemetria

Adicionar em `config/config.exs`:

```elixir
config :w_core, WCore.Repo,
  database: Path.expand("../priv/repo/w_core_#{config_env()}.db", __DIR__),
  pool_size: 5,
  # WAL mode: permite leituras concorrentes durante escritas
  journal_mode: :wal,
  # Cache de 64MB para queries frequentes
  cache_size: -64000,
  # Sync normal: balanco entre performance e durabilidade
  synchronous: :normal,
  # Temp store em memoria
  temp_store: :memory
```

**Por que WAL?** Write-Ahead Logging permite que o GenServer de ingestao (Passo 2) grave
dados enquanto o LiveView Dashboard (Passo 3) le sem bloqueio. Critico para um sistema
de telemetria em tempo real.

---

## 1.2 Autenticacao com `phx.gen.auth`

### Geracao

```bash
mix phx.gen.auth Accounts User users
```

Isso gera:
- Contexto `WCore.Accounts` com schema `User`
- Migrations para `users` e `users_tokens`
- LiveViews de registro, login, confirmacao, reset de senha
- Plugs de autenticacao (`fetch_current_scope_from_session`, `require_authenticated_user`)

### Estrutura de Rotas Resultante

```elixir
# router.ex
scope "/", WCoreWeb do
  pipe_through [:browser]

  # Rotas publicas
  get "/", PageController, :home
end

scope "/", WCoreWeb do
  pipe_through [:browser, :redirect_if_user_is_authenticated]

  live_session :redirect_if_user_is_authenticated,
    on_mount: [{WCoreWeb.UserAuth, :redirect_if_user_is_authenticated}] do
    live "/users/register", UserRegistrationLive, :new
    live "/users/log-in", UserLoginLive, :new
    live "/users/reset-password", UserResetPasswordLive, :new
  end
end

scope "/", WCoreWeb do
  pipe_through [:browser, :require_authenticated_user]

  live_session :require_authenticated_user,
    on_mount: [{WCoreWeb.UserAuth, :ensure_authenticated}] do
    # Dashboard e rotas protegidas (Passo 3)
    live "/dashboard", DashboardLive, :index
    live "/users/settings", UserSettingsLive, :edit
  end
end
```

### Customizacao do User Schema

Adicionar campo `role` para controle de acesso futuro:

```elixir
# Em uma migration separada apos gen.auth
alter table(:users) do
  add :role, :string, default: "operator", null: false
  add :name, :string
end
```

---

## 1.3 Limites de Dominio

### Arquitetura de Contextos

```
lib/w_core/
  accounts/           # Gerado pelo phx.gen.auth
    user.ex
    user_token.ex
    user_notifier.ex

  telemetry/           # Dominio de Telemetria (isolado)
    machine.ex         # Schema: maquinas monitoradas
    pulse.ex           # Schema: leituras/eventos de sensores
    telemetry.ex       # Contexto: funcoes publicas

  ingestion/           # Camada OTP (Passo 2)
    supervisor.ex
    pulse_server.ex
    write_behind.ex
```

**Regra:** `Telemetry` nunca importa `Accounts`. `Accounts` nunca importa `Telemetry`.
A unica ponte e a camada web (LiveView) que consulta ambos.

### Schemas Iniciais

```elixir
# lib/w_core/telemetry/machine.ex
defmodule WCore.Telemetry.Machine do
  use Ecto.Schema
  import Ecto.Changeset

  schema "machines" do
    field :name, :string
    field :identifier, :string  # ex: "CNC-001", "PRESS-042"
    field :type, :string        # ex: "cnc", "press", "conveyor"
    field :status, :string, default: "offline"  # online | offline | alert
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

# lib/w_core/telemetry/pulse.ex
defmodule WCore.Telemetry.Pulse do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pulses" do
    field :value, :float
    field :unit, :string          # ex: "rpm", "celsius", "bar"
    field :sensor, :string        # ex: "temp_main", "pressure_1"
    field :recorded_at, :utc_datetime

    belongs_to :machine, WCore.Telemetry.Machine
    timestamps(type: :utc_datetime)
  end

  def changeset(pulse, attrs) do
    pulse
    |> cast(attrs, [:value, :unit, :sensor, :recorded_at, :machine_id])
    |> validate_required([:value, :unit, :sensor, :machine_id])
    |> foreign_key_constraint(:machine_id)
  end
end
```

### Migration

```elixir
# priv/repo/migrations/XXX_create_telemetry_tables.exs
defmodule WCore.Repo.Migrations.CreateTelemetryTables do
  use Ecto.Migration

  def change do
    create table(:machines) do
      add :name, :string, null: false
      add :identifier, :string, null: false
      add :type, :string, null: false
      add :status, :string, default: "offline", null: false
      add :metadata, :map, default: %{}
      timestamps(type: :utc_datetime)
    end

    create unique_index(:machines, [:identifier])

    create table(:pulses) do
      add :value, :float, null: false
      add :unit, :string, null: false
      add :sensor, :string, null: false
      add :recorded_at, :utc_datetime, null: false
      add :machine_id, references(:machines, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create index(:pulses, [:machine_id])
    create index(:pulses, [:recorded_at])
    create index(:pulses, [:machine_id, :sensor, :recorded_at])
  end
end
```

---

## 1.4 Contexto Telemetry (API Publica)

```elixir
# lib/w_core/telemetry/telemetry.ex
defmodule WCore.Telemetry do
  @moduledoc """
  Contexto de Telemetria. Interface publica para operacoes
  com maquinas e pulsos de sensores.
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

  def update_machine_status(%Machine{} = machine, status) do
    machine
    |> Machine.changeset(%{status: status})
    |> Repo.update()
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
end
```

---

## 1.5 Checklist de Entrega

- [ ] `mix ecto.create` e `mix ecto.migrate` rodam sem erro
- [ ] `mix phx.gen.auth Accounts User users` executado e integrado
- [ ] Rotas protegidas (`/dashboard`) redirecionam para login
- [ ] Rotas publicas (`/`) acessiveis sem autenticacao
- [ ] Schemas `Machine` e `Pulse` com migrations aplicadas
- [ ] Contexto `WCore.Telemetry` com funcoes CRUD basicas
- [ ] Indices no banco para queries de telemetria performaticas
- [ ] WAL mode habilitado no SQLite
- [ ] `mix precommit` passa sem warnings

---

## Diagrama de Dependencias

```
                    WCoreWeb (Router/LiveViews)
                   /                            \
                  v                              v
        WCore.Accounts              WCore.Telemetry
        (User, Token)              (Machine, Pulse)
                  \                              /
                   v                            v
                        WCore.Repo (SQLite3)
```

**Proximo:** Passo 2 - O Coracao da Usina (OTP & ETS)
