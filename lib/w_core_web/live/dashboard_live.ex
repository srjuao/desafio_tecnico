defmodule WCoreWeb.DashboardLive do
  use WCoreWeb, :live_view

  alias WCore.Telemetry

  @impl true
  def mount(_params, _session, socket) do
    machines = Telemetry.list_machines()

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:machines, machines)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <div class="flex justify-between items-center">
          <h1 class="text-2xl font-bold">Sala de Controle</h1>
          <span class="badge badge-info">
            {length(@machines)} maquinas
          </span>
        </div>

        <div :if={@machines == []} class="text-center py-12 text-base-content/60">
          <.icon name="hero-cpu-chip" class="size-12 mx-auto mb-4" />
          <p class="text-lg">Nenhuma maquina cadastrada ainda.</p>
          <p class="text-sm mt-2">Os dados aparecerao aqui quando o sistema de ingestao estiver ativo.</p>
        </div>

        <div :if={@machines != []} class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <div :for={machine <- @machines} class="card bg-base-200 shadow-lg border-l-4 border-base-300">
            <div class="card-body p-4">
              <h3 class="card-title text-base">{machine.name}</h3>
              <p class="text-sm text-base-content/60">{machine.identifier}</p>
              <div class="flex justify-between items-center mt-2">
                <span class="badge badge-sm badge-ghost">{machine.type}</span>
                <span class={["badge badge-sm", status_class(machine.status)]}>
                  {machine.status}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp status_class("online"), do: "badge-success"
  defp status_class("alert"), do: "badge-warning"
  defp status_class(_), do: "badge-ghost"
end
