defmodule WCoreWeb.DashboardLive do
  @moduledoc """
  Dashboard em tempo real da Planta 42.
  """
  use WCoreWeb, :live_view

  import WCoreWeb.PlantComponents

  alias WCore.Telemetry.Cache

  @pubsub WCore.PubSub
  @topic "telemetry:nodes"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(@pubsub, @topic)
      # Framerate da Tela: 10 FPS (100ms) para dados rolando loucamente
      :timer.send_interval(100, :tick)
    end

    nodes = load_nodes_from_ets()

    socket =
      socket
      |> assign(:nodes, nodes)
      |> assign(:flashing, MapSet.new())
      |> assign(:stats, compute_stats(nodes))
      |> assign(:speed, 1.2)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="dashboard-wrapper" phx-hook="Iridescence" data-color="[59, 130, 246]" data-speed={@speed} data-amplitude="0.5" class="min-h-screen bg-transparent relative overflow-hidden">
      <%!-- Fundo escuro fixo em caso de falha do WebGL --%>
      <div class="absolute inset-0 bg-[#0a0a0c] pointer-events-none z-0"></div>

      <%!-- Cabeçalho --%>
      <header class="bg-black/20 backdrop-blur border-b border-white/5 px-6 py-4 sticky top-0 z-40">
        <div class="flex items-center justify-between max-w-7xl mx-auto">
          <div>
            <h1 class="text-lg font-bold text-white tracking-tight">W-CORE</h1>
            <p class="text-xs text-blue-400 uppercase tracking-widest"><%= gettext("Control Center") %></p>
          </div>
          <div class="flex items-center gap-6">
            <div class="flex items-center gap-2">
              <span class="w-2 h-2 rounded-full bg-blue-500 shadow-[0_0_8px_rgba(59,130,246,0.8)] animate-pulse"></span>
              <span class="text-xs text-gray-300 uppercase font-bold tracking-tighter hidden sm:inline"><%= gettext("Real-time Monitoring") %></span>
            </div>
            
            <.link href={~p"/users/log-out"} method="delete" class="flex items-center gap-2 text-xs font-bold text-gray-400 hover:text-white transition-colors border-l border-[#2d2d33] pl-6">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"></path></svg>
              <%= gettext("Log out") %>
            </.link>
          </div>
        </div>
      </header>

      <main class="relative z-10 max-w-7xl mx-auto px-6 py-6 space-y-6">

        <%!-- Estatísticas --%>
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
          <.stat_card label={gettext("Total nodes")} value={@stats.total} />
          <.stat_card label={gettext("Operating")}
            value={@stats.ok} color="emerald" />
          <.stat_card label={gettext("Alarm")}
            value={@stats.warning} color="amber" />
          <.stat_card label={gettext("Critical")}
            value={@stats.critical} color="red" />
        </div>

        <%!-- Grid de máquinas --%>
        <div>
          <h2 class="text-sm font-bold text-white mb-3 uppercase tracking-wider flex items-center gap-2">
            <svg class="w-4 h-4 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z"></path></svg>
            <%= gettext("Active sensors") %>
          </h2>
          <%= if map_size(@nodes) == 0 do %>
            <div class="text-center py-12 text-gray-400 text-sm">
              Aguardando heartbeats dos sensores...
            </div>
          <% else %>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
              <%= for {node_id, node} <- @nodes do %>
                <.machine_card
                  node={node}
                  flash={MapSet.member?(@flashing, node_id)}
                />
              <% end %>
            </div>
          <% end %>
        </div>

      </main>
    </div>
    """
  end

  @impl true
  def handle_info({:node_status_changed, %{node_id: node_id, status: new_status}}, socket) do
    # Atualiza cirurgicamente só o node afetado
    # Na estrutura do usuário, a chave no socket.assigns.nodes é o node_id
    nodes =
      case Cache.get(node_id) do
        nil    -> socket.assigns.nodes
        record -> Map.put(socket.assigns.nodes, node_id, Cache.to_map(record))
      end

    # Flash visual se virou critical
    flashing =
      if new_status == "critical" do
        Process.send_after(self(), {:clear_flash, node_id}, 1500)
        MapSet.put(socket.assigns.flashing, node_id)
      else
        socket.assigns.flashing
      end

    stats = compute_stats(nodes)

    socket =
      socket
      |> assign(:nodes, nodes)
      |> assign(:flashing, flashing)
      |> assign(:stats, stats)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:clear_flash, node_id}, socket) do
    flashing = MapSet.delete(socket.assigns.flashing, node_id)
    {:noreply, assign(socket, :flashing, flashing)}
  end

  @impl true
  def handle_info(:tick, socket) do
    # Framerate Loop: puxa tudo do ETS silenciosamente a cada 100ms
    nodes = load_nodes_from_ets()
    stats = compute_stats(nodes)

    socket =
      socket
      |> assign(:nodes, nodes)
      |> assign(:stats, stats)

    {:noreply, socket}
  end

  # --- Privado ---

  defp load_nodes_from_ets do
    Cache.all()
    |> Enum.map(&Cache.to_map/1)
    |> Map.new(fn node -> {node.node_id, node} end)
  end

  defp compute_stats(nodes) do
    values = Map.values(nodes)
    %{
      total:    length(values),
      ok:       Enum.count(values, &(&1.status == "ok")),
      warning:  Enum.count(values, &(&1.status == "warning")),
      critical: Enum.count(values, &(&1.status == "critical"))
    }
  end

  @impl true
  def handle_event("update_speed", %{"value" => v}, socket) do
    speed = case Float.parse(to_string(v)) do
      {float, _} -> float
      :error -> 1.2
    end
    {:noreply, assign(socket, speed: speed)}
  end
end
