# Passo 3: A Sala de Controle (Design System e LiveView)

## Objetivo

Criar o Dashboard em tempo real para usuarios autenticados usando LiveView.
A interface le dados quentes do ETS e reage instantaneamente via PubSub
quando novos pulsos chegam.

---

## 3.1 Arquitetura da LiveView

### Principio: Zero Queries ao SQLite para Dados Recentes

```
LiveView mount/0
  -> :ets.match_object(:pulses_hot, ...) para estado inicial
  -> PubSub.subscribe("machines:status") para status geral
  -> PubSub.subscribe("machines:#{id}") para pulsos especificos

Cada {:new_pulse, ...} do PubSub
  -> Atualiza assigns diretamente (sem query ao banco)
  -> push_event para atualizar graficos JS
```

---

## 3.2 Dashboard LiveView

```elixir
# lib/w_core_web/live/dashboard_live.ex
defmodule WCoreWeb.DashboardLive do
  use WCoreWeb, :live_view

  alias WCore.Ingestion.{PulseServer, TableManager}
  alias WCore.Telemetry

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(WCore.PubSub, "machines:status")
    end

    machines = load_machines_with_status()

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> stream(:machines, machines)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <div class="flex justify-between items-center">
          <h1 class="text-2xl font-bold">Sala de Controle</h1>
          <span class="badge badge-info">
            {machine_count(@streams.machines)} maquinas
          </span>
        </div>

        <div id="machines" phx-update="stream" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <div :for={{dom_id, machine} <- @streams.machines} id={dom_id}>
            <.machine_card machine={machine} />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # --- Componentes ---

  defp machine_card(assigns) do
    ~H"""
    <div class={[
      "card bg-base-200 shadow-lg border-l-4 transition-all",
      status_border_color(@machine.status)
    ]}>
      <div class="card-body p-4">
        <div class="flex justify-between items-start">
          <div>
            <h3 class="card-title text-base">{@machine.name}</h3>
            <p class="text-sm text-base-content/60">{@machine.identifier}</p>
          </div>
          <.status_badge status={@machine.status} />
        </div>

        <div :if={@machine.last_pulse} class="mt-3 space-y-1">
          <div class="flex justify-between text-sm">
            <span class="text-base-content/70">{@machine.last_pulse.sensor}</span>
            <span class="font-mono font-semibold">
              {@machine.last_pulse.value} {@machine.last_pulse.unit}
            </span>
          </div>
          <div class="text-xs text-base-content/50">
            {relative_time(@machine.last_seen)}
          </div>
        </div>

        <div class="card-actions justify-end mt-2">
          <.link navigate={~p"/machines/#{@machine.id}"} class="btn btn-sm btn-ghost">
            Detalhes
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp status_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm", status_badge_class(@status)]}>
      {@status}
    </span>
    """
  end

  defp status_border_color(:online), do: "border-success"
  defp status_border_color(:alert), do: "border-warning"
  defp status_border_color(_), do: "border-base-300"

  defp status_badge_class(:online), do: "badge-success"
  defp status_badge_class(:alert), do: "badge-warning"
  defp status_badge_class(_), do: "badge-ghost"

  defp relative_time(nil), do: "—"
  defp relative_time(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)
    cond do
      diff < 5 -> "agora"
      diff < 60 -> "#{diff}s atras"
      diff < 3600 -> "#{div(diff, 60)}min atras"
      true -> "#{div(diff, 3600)}h atras"
    end
  end

  defp machine_count(stream), do: Enum.count(stream.inserts)

  # --- Handlers PubSub ---

  @impl true
  def handle_info({:machine_status_changed, machine_id, status}, socket) do
    machine = build_machine_view(machine_id, status)
    {:noreply, stream_insert(socket, :machines, machine)}
  end

  def handle_info({:new_pulse, machine_id, pulse_data}, socket) do
    machine = build_machine_view(machine_id, :online, pulse_data)
    {:noreply, stream_insert(socket, :machines, machine)}
  end

  # --- Data Loading ---

  defp load_machines_with_status do
    machines = Telemetry.list_machines()
    status_table = TableManager.status_table_name()

    Enum.map(machines, fn machine ->
      case :ets.lookup(status_table, machine.id) do
        [{_, status_data}] ->
          Map.merge(machine, %{
            status: status_data.status,
            last_seen: status_data.last_seen,
            last_pulse: get_last_pulse(machine.id)
          })

        [] ->
          Map.merge(machine, %{status: :offline, last_seen: nil, last_pulse: nil})
      end
    end)
  end

  defp get_last_pulse(machine_id) do
    case PulseServer.get_recent(machine_id, "_any", 1) do
      [pulse | _] -> pulse
      [] -> nil
    end
  end

  defp build_machine_view(machine_id, status, pulse \\ nil) do
    machine = Telemetry.get_machine!(machine_id)
    %{
      id: machine.id,
      name: machine.name,
      identifier: machine.identifier,
      type: machine.type,
      status: status,
      last_seen: DateTime.utc_now(),
      last_pulse: pulse
    }
  end
end
```

---

## 3.3 Detalhe da Maquina (com Graficos em Tempo Real)

```elixir
# lib/w_core_web/live/machine_live.ex
defmodule WCoreWeb.MachineLive do
  use WCoreWeb, :live_view

  alias WCore.Ingestion.PulseServer
  alias WCore.Telemetry

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    machine = Telemetry.get_machine!(id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(WCore.PubSub, "machines:#{machine.id}")
    end

    recent_pulses = PulseServer.get_recent(machine.id, "temp", 50)

    {:ok,
     socket
     |> assign(:page_title, machine.name)
     |> assign(:machine, machine)
     |> assign(:pulses, recent_pulses)
     |> push_event("chart:init", %{data: format_chart_data(recent_pulses)})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <div class="flex items-center gap-4">
          <.link navigate={~p"/dashboard"} class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="size-4" /> Voltar
          </.link>
          <h1 class="text-2xl font-bold">{@machine.name}</h1>
          <span class="badge badge-outline">{@machine.identifier}</span>
        </div>

        <%!-- Grafico de pulsos em tempo real --%>
        <div class="card bg-base-200 p-4">
          <h2 class="text-lg font-semibold mb-4">Leituras em Tempo Real</h2>
          <canvas
            id="pulse-chart"
            phx-hook="PulseChart"
            phx-update="ignore"
            class="w-full h-64"
          ></canvas>
        </div>

        <%!-- Tabela de pulsos recentes --%>
        <div class="card bg-base-200 p-4">
          <h2 class="text-lg font-semibold mb-4">Ultimos Pulsos</h2>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Sensor</th>
                  <th>Valor</th>
                  <th>Unidade</th>
                  <th>Horario</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={pulse <- Enum.take(@pulses, 20)}>
                  <td>{pulse.sensor}</td>
                  <td class="font-mono">{pulse.value}</td>
                  <td>{pulse.unit}</td>
                  <td class="text-base-content/60">
                    {Calendar.strftime(pulse.recorded_at, "%H:%M:%S")}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info({:new_pulse, _machine_id, pulse_data}, socket) do
    pulses = [pulse_data | Enum.take(socket.assigns.pulses, 99)]

    {:noreply,
     socket
     |> assign(:pulses, pulses)
     |> push_event("chart:new_point", %{
       x: DateTime.to_iso8601(pulse_data.recorded_at),
       y: pulse_data.value,
       sensor: pulse_data.sensor
     })}
  end

  defp format_chart_data(pulses) do
    Enum.map(pulses, fn p ->
      %{x: DateTime.to_iso8601(p.recorded_at), y: p.value, sensor: p.sensor}
    end)
  end
end
```

---

## 3.4 Hook JS para Graficos

```javascript
// assets/js/hooks/pulse_chart.js
export const PulseChart = {
  mounted() {
    this.canvas = this.el
    this.ctx = this.canvas.getContext("2d")
    this.points = []
    this.maxPoints = 100

    this.handleEvent("chart:init", ({ data }) => {
      this.points = data.reverse()
      this.draw()
    })

    this.handleEvent("chart:new_point", (point) => {
      this.points.push(point)
      if (this.points.length > this.maxPoints) this.points.shift()
      this.draw()
    })

    this.resizeObserver = new ResizeObserver(() => this.draw())
    this.resizeObserver.observe(this.el)
  },

  draw() {
    const { canvas, ctx, points } = this
    const dpr = window.devicePixelRatio || 1
    const w = canvas.clientWidth * dpr
    const h = canvas.clientHeight * dpr
    canvas.width = w
    canvas.height = h
    ctx.scale(dpr, dpr)

    const cw = canvas.clientWidth
    const ch = canvas.clientHeight
    const padding = 40

    ctx.clearRect(0, 0, cw, ch)

    if (points.length < 2) return

    const values = points.map(p => p.y)
    const min = Math.min(...values) - 5
    const max = Math.max(...values) + 5
    const range = max - min || 1

    // Grid lines
    ctx.strokeStyle = "rgba(128,128,128,0.15)"
    ctx.lineWidth = 1
    for (let i = 0; i <= 4; i++) {
      const y = padding + (ch - 2 * padding) * (i / 4)
      ctx.beginPath()
      ctx.moveTo(padding, y)
      ctx.lineTo(cw - padding, y)
      ctx.stroke()

      ctx.fillStyle = "rgba(128,128,128,0.6)"
      ctx.font = "11px monospace"
      ctx.textAlign = "right"
      ctx.fillText((max - (range * i / 4)).toFixed(1), padding - 6, y + 4)
    }

    // Data line
    ctx.beginPath()
    ctx.strokeStyle = "#7c3aed"
    ctx.lineWidth = 2
    ctx.lineJoin = "round"

    points.forEach((p, i) => {
      const x = padding + (cw - 2 * padding) * (i / (points.length - 1))
      const y = padding + (ch - 2 * padding) * (1 - (p.y - min) / range)
      if (i === 0) ctx.moveTo(x, y)
      else ctx.lineTo(x, y)
    })
    ctx.stroke()

    // Gradient fill
    const gradient = ctx.createLinearGradient(0, padding, 0, ch - padding)
    gradient.addColorStop(0, "rgba(124, 58, 237, 0.15)")
    gradient.addColorStop(1, "rgba(124, 58, 237, 0)")
    ctx.lineTo(cw - padding, ch - padding)
    ctx.lineTo(padding, ch - padding)
    ctx.closePath()
    ctx.fillStyle = gradient
    ctx.fill()
  },

  destroyed() {
    this.resizeObserver.disconnect()
  }
}
```

---

## 3.5 Rotas

```elixir
# Em router.ex, dentro do live_session :require_authenticated_user
live "/dashboard", DashboardLive, :index
live "/machines/:id", MachineLive, :show
```

---

## 3.6 Como Evitar Gargalos no PubSub

### Problema Potencial
Com 100 maquinas a 1 pulso/segundo, sao 100 mensagens/segundo no PubSub.
Se 50 usuarios estao no Dashboard, cada um recebe 100 msgs/s = 5.000 msgs/s total.

### Estrategia de Mitigacao

**1. Topicos Granulares**
```
"machines:status"     -> Apenas mudancas de status (raro: ~1/min)
"machines:42"         -> Pulsos da maquina 42 (so quem esta vendo detalhes)
```

O Dashboard principal assina apenas `"machines:status"`, NAO os pulsos individuais.
So a MachineLive assina `"machines:#{id}"` para a maquina especifica.

**2. Throttling no PulseServer**
```elixir
# Nao fazer broadcast a cada pulso. Throttle de 1 por segundo:
defp maybe_broadcast(state, pulse_data) do
  now = System.monotonic_time(:millisecond)
  if now - state.last_broadcast > 1_000 do
    Phoenix.PubSub.broadcast(...)
    %{state | last_broadcast: now}
  else
    state
  end
end
```

**3. LiveView leve**
- `stream/3` para listas grandes (nao carrega tudo na memoria do processo)
- `push_event/3` para graficos JS (o LiveView nao renderiza o canvas)
- Nenhum assign com listas grandes de pulsos no socket

### Calculo de Carga

| Cenario | Mensagens/s | Aceitavel? |
|---------|------------|------------|
| 100 maquinas, Dashboard only | 100 status/min = ~2/s | Sim |
| 1 usuario em MachineLive | 1 pulso/s | Sim |
| 50 usuarios em MachineLive(s) | 50 pulsos/s (pior caso) | Sim |
| Sem throttle, todos em Dashboard | 100 x 50 = 5000/s | NAO |

Com topicos granulares + throttle, o pior caso real e ~100 msgs/s. Aceitavel.

---

## 3.7 Design System (Componentes)

Componentes adicionais para `core_components.ex`:

```elixir
# Stat card para metricas
attr :label, :string, required: true
attr :value, :string, required: true
attr :icon, :string, default: nil
attr :trend, :string, default: nil  # "up" | "down" | nil

def stat_card(assigns) do
  ~H"""
  <div class="stat bg-base-200 rounded-box">
    <div :if={@icon} class="stat-figure text-primary">
      <.icon name={@icon} class="size-8" />
    </div>
    <div class="stat-title">{@label}</div>
    <div class="stat-value">{@value}</div>
    <div :if={@trend} class={["stat-desc", trend_color(@trend)]}>
      {trend_icon(@trend)} {trend_label(@trend)}
    </div>
  </div>
  """
end
```

---

## 3.8 Checklist de Entrega

- [ ] `DashboardLive` renderiza cards de maquinas com status em tempo real
- [ ] `MachineLive` mostra graficos de pulsos atualizados via PubSub
- [ ] Hook `PulseChart` desenha grafico com Canvas 2D
- [ ] PubSub usa topicos granulares (status vs pulsos individuais)
- [ ] Throttle de broadcast: maximo 1 msg/s por maquina
- [ ] `stream/3` usado para listas de maquinas (sem acumular no socket)
- [ ] Rotas protegidas por autenticacao
- [ ] UI responsiva com daisyUI (cards, badges, tables)
- [ ] Background iridescente visivel atras do conteudo
- [ ] `mix precommit` passa

**Proximo:** Passo 4 - Simulacao de Caos (Testes Rigorosos)
