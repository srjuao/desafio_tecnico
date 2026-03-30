# Passo 5: O Empacotamento para o Edge (Infraestrutura)

## Objetivo

Criar o Dockerfile para `mix release` otimizada, garantir persistencia
do banco SQLite via volumes, e documentar a arquitetura final.

---

## 5.1 Mix Release

### Configuracao em `mix.exs`

```elixir
def project do
  [
    ...
    releases: [
      w_core: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent]
      ]
    ]
  ]
end
```

### Runtime Config (`config/runtime.exs`)

```elixir
if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      Path.join(System.get_env("DATA_DIR", "/app/data"), "w_core.db")

  config :w_core, WCore.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "5")),
    journal_mode: :wal,
    cache_size: -64000,
    synchronous: :normal,
    temp_store: :memory

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE not set"

  host = System.get_env("PHX_HOST", "localhost")
  port = String.to_integer(System.get_env("PORT", "4000"))

  config :w_core, WCoreWeb.Endpoint,
    url: [host: host, port: port],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true
end
```

---

## 5.2 Dockerfile (Multi-Stage)

```dockerfile
# ============================================
# Stage 1: Build
# ============================================
FROM hexpm/elixir:1.15.7-erlang-26.2.1-debian-bookworm-20240130 AS build

RUN apt-get update -y && \
    apt-get install -y build-essential git && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Instalar dependencias do Mix
RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# Copiar manifesto de dependencias primeiro (cache layer)
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mkdir config

# Copiar configs de compilacao
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

# Copiar codigo e assets
COPY lib lib
COPY priv priv
COPY assets assets

# Build assets
RUN mix assets.deploy

# Compilar e gerar digest
RUN mix compile

# Copiar runtime config
COPY config/runtime.exs config/

# Gerar release
RUN mix release

# ============================================
# Stage 2: Runtime
# ============================================
FROM debian:bookworm-slim AS runtime

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

# Usuario nao-root
RUN groupadd -r app && useradd -r -g app -d /app app

# Diretorio de dados com permissoes corretas
RUN mkdir -p /app/data && chown -R app:app /app

# Copiar release do stage de build
COPY --from=build --chown=app:app /app/_build/prod/rel/w_core ./

USER app

# Volume para persistencia do SQLite
VOLUME ["/app/data"]

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:${PORT:-4000}/health || exit 1

ENV DATABASE_PATH=/app/data/w_core.db
ENV PHX_HOST=localhost
ENV PORT=4000

EXPOSE 4000

CMD ["bin/w_core", "start"]
```

---

## 5.3 Docker Compose

```yaml
# docker-compose.yml
version: "3.8"

services:
  w_core:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "${PORT:-4000}:4000"
    environment:
      - SECRET_KEY_BASE=${SECRET_KEY_BASE}
      - DATABASE_PATH=/app/data/w_core.db
      - PHX_HOST=${PHX_HOST:-localhost}
      - PORT=4000
    volumes:
      # Volume nomeado para persistencia do SQLite
      - w_core_data:/app/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s

volumes:
  w_core_data:
    driver: local
```

### Comandos

```bash
# Gerar secret
export SECRET_KEY_BASE=$(mix phx.gen.secret)

# Build e run
docker compose up -d --build

# Ver logs
docker compose logs -f w_core

# Rodar migrations no container
docker compose exec w_core bin/w_core eval "WCore.Release.migrate()"

# Backup do banco
docker compose exec w_core cp /app/data/w_core.db /app/data/w_core_backup.db
docker cp $(docker compose ps -q w_core):/app/data/w_core_backup.db ./backup.db
```

---

## 5.4 Modulo Release (Migrations em Producao)

```elixir
# lib/w_core/release.ex
defmodule WCore.Release do
  @moduledoc """
  Funcoes para executar em producao via:
    bin/w_core eval "WCore.Release.migrate()"
  """
  @app :w_core

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
```

---

## 5.5 Health Check Endpoint

```elixir
# Em router.ex
scope "/", WCoreWeb do
  pipe_through :api

  get "/health", HealthController, :check
end

# lib/w_core_web/controllers/health_controller.ex
defmodule WCoreWeb.HealthController do
  use WCoreWeb, :controller

  def check(conn, _params) do
    # Verificar banco
    db_ok =
      try do
        WCore.Repo.query!("SELECT 1")
        true
      rescue
        _ -> false
      end

    # Verificar ETS
    ets_ok = :ets.info(:pulses_hot) != :undefined

    status = if db_ok and ets_ok, do: 200, else: 503

    json(conn, %{
      status: if(status == 200, do: "healthy", else: "unhealthy"),
      checks: %{
        database: db_ok,
        ets: ets_ok
      },
      timestamp: DateTime.utc_now()
    })
  end
end
```

---

## 5.6 Persistencia do SQLite - Consideracoes

### Por que Volume Nomeado?

| Opcao | Vantagem | Problema |
|-------|----------|---------|
| Bind mount (`./data:/app/data`) | Facil backup | Permissoes do host podem conflitar |
| Volume nomeado | Docker gerencia permissoes | Backup requer `docker cp` |
| tmpfs | Performance maxima | Dados perdidos ao reiniciar |

**Escolha: Volume nomeado** — Docker gerencia as permissoes automaticamente,
e o SQLite com WAL mode funciona sem problemas de lock.

### WAL Mode em Container

O SQLite em WAL mode cria dois arquivos auxiliares:
- `w_core.db-wal` (Write-Ahead Log)
- `w_core.db-shm` (Shared Memory)

**Todos devem estar no mesmo volume.** O `DATABASE_PATH` aponta para dentro
de `/app/data/`, que e o volume montado, garantindo que WAL e SHM
coexistam no mesmo filesystem.

### Backup em Producao

```bash
# Backup quente (WAL mode permite)
sqlite3 /app/data/w_core.db ".backup '/app/data/backup.db'"

# Ou via Elixir
bin/w_core eval "WCore.Repo.query!(\"VACUUM INTO '/app/data/backup.db'\")"
```

---

## 5.7 Diagrama Arquitetural

```
                         ┌─────────────────────────────────────────────────┐
                         │              Docker Container                   │
                         │                                                 │
   HTTP/WS               │  ┌──────────────────────────────────────────┐   │
 ──────────────────────────►│          Bandit HTTP Server               │   │
                         │  │          (port 4000)                      │   │
                         │  └──────────┬───────────────────────────────┘   │
                         │             │                                   │
                         │  ┌──────────▼───────────────────────────────┐   │
                         │  │        Phoenix Endpoint                   │   │
                         │  │  ┌─────────────┐  ┌──────────────────┐   │   │
                         │  │  │   Router     │  │   LiveView WS    │   │   │
                         │  │  │  /api/pulse  │  │   /live          │   │   │
                         │  │  └──────┬──────┘  └────────┬─────────┘   │   │
                         │  └─────────┼──────────────────┼─────────────┘   │
                         │            │                  │                  │
                         │  ┌─────────▼──────────────────▼─────────────┐   │
                         │  │           OTP Application                │   │
                         │  │                                          │   │
                         │  │  ┌─────────────────────────────────┐     │   │
                         │  │  │     Ingestion Supervisor         │     │   │
                         │  │  │                                  │     │   │
                         │  │  │  ┌──────────────┐                │     │   │
                         │  │  │  │ TableManager  │─── owns ──┐   │     │   │
                         │  │  │  └──────────────┘            │   │     │   │
                         │  │  │                              ▼   │     │   │
                         │  │  │  ┌──────────────┐    ┌──────────┐│     │   │
                         │  │  │  │DynamicSupvsr │    │   ETS    ││     │   │
                         │  │  │  │              │    │          ││     │   │
                         │  │  │  │ PulseServer1 │──►│:pulses   ││     │   │
                         │  │  │  │ PulseServer2 │──►│ _hot     ││     │   │
                         │  │  │  │ PulseServerN │──►│          ││     │   │
                         │  │  │  └──────────────┘    │:machines ││     │   │
                         │  │  │                      │ _status  ││     │   │
                         │  │  │  ┌──────────────┐    └──────────┘│     │   │
                         │  │  │  │ WriteBehind  │────────┐       │     │   │
                         │  │  │  │ (10s flush)  │        │       │     │   │
                         │  │  │  └──────────────┘        │       │     │   │
                         │  │  └──────────────────────────┼───────┘     │   │
                         │  │                             │             │   │
                         │  │  ┌──────────────┐           │             │   │
                         │  │  │ Phoenix.PubSub│◄──broadcast──          │   │
                         │  │  │  (pg)        │                        │   │
                         │  │  └──────┬───────┘                        │   │
                         │  │         │ subscribe                      │   │
                         │  │         ▼                                │   │
                         │  │  ┌──────────────┐                        │   │
                         │  │  │  LiveViews    │ reads from ETS        │   │
                         │  │  │  Dashboard    │─────────────────────► │   │
                         │  │  │  MachineLive  │                       │   │
                         │  │  └──────────────┘                        │   │
                         │  │                                          │   │
                         │  │  ┌──────────────┐       ┌────────────┐   │   │
                         │  │  │  Ecto Repo   │──────►│  SQLite3   │   │   │
                         │  │  │              │       │  (WAL)     │   │   │
                         │  │  └──────────────┘       └─────┬──────┘   │   │
                         │  └───────────────────────────────┼──────────┘   │
                         │                                  │              │
                         │                    ┌─────────────▼──────────┐   │
                         │                    │  /app/data/ (Volume)    │   │
                         │                    │  ├── w_core.db         │   │
                         │                    │  ├── w_core.db-wal     │   │
                         │                    │  └── w_core.db-shm     │   │
                         │                    └────────────────────────┘   │
                         └─────────────────────────────────────────────────┘
```

### Fluxo de Dados

```
Sensor/API ──POST──► PulseController ──► PulseServer ──► ETS (hot)
                                              │              │
                                              │         LiveView (le)
                                              │              │
                                         PubSub ◄────────────┘
                                              │         (broadcast)
                                              ▼
                                         LiveView (update)
                                              │
                                         Browser (re-render)

                     WriteBehind ──timer──► ETS (read) ──► SQLite (cold)
```

---

## 5.8 .dockerignore

```
# .dockerignore
_build/
deps/
.git/
.gitignore
node_modules/
priv/static/assets/
engine_v1/
hb_cache/
homebrew/
asdf/
asdf_data/
*.db
*.db-wal
*.db-shm
docs/
test/
.formatter.exs
README.md
AGENTS.md
```

---

## 5.9 Checklist de Entrega

- [ ] `mix release` gera release funcional
- [ ] `WCore.Release.migrate/0` roda migrations em producao
- [ ] Dockerfile multi-stage com imagem final < 150MB
- [ ] Volume `/app/data/` persiste SQLite entre restarts
- [ ] WAL files no mesmo volume do banco
- [ ] Health check `/health` verifica banco e ETS
- [ ] `docker compose up` inicia aplicacao completa
- [ ] `docker compose exec w_core bin/w_core eval "WCore.Release.migrate()"` funciona
- [ ] Container roda como usuario nao-root
- [ ] Diagrama arquitetural documentado

---

## Resumo da Evolucao Completa

| Passo | Entrega | Tecnologias |
|-------|---------|-------------|
| 1. Fundacao | Auth + Schemas + SQLite WAL | phx.gen.auth, Ecto, SQLite3 |
| 2. OTP & ETS | Ingestao em tempo real | GenServer, DynamicSupervisor, ETS, WriteBehind |
| 3. LiveView DS | Dashboard reativo | LiveView, PubSub, Streams, Canvas hooks |
| 4. Testes | 10k eventos sem perda | ExUnit, Task.async, stress test |
| 5. Infra | Container pronto para deploy | mix release, Docker, Volume |
