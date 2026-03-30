defmodule WCoreWeb.PlantComponents do
  @moduledoc """
  Design System da Planta 42.

  Componentes HEEx puros — sem dependências de UI externas.
  """
  use Phoenix.Component

  # --- Badge de status ---

  attr :status, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium",
      badge_color(@status)
    ]}>
      <span class={["w-1.5 h-1.5 rounded-full mr-1.5", dot_color(@status)]}></span>
      <%= @status %>
    </span>
    """
  end

  defp badge_color("ok"),       do: "bg-green-100 text-green-800"
  defp badge_color("warning"),  do: "bg-yellow-100 text-yellow-800"
  defp badge_color("critical"), do: "bg-red-100 text-red-800"
  defp badge_color(_),          do: "bg-gray-100 text-gray-600"

  defp dot_color("ok"),         do: "bg-green-500"
  defp dot_color("warning"),    do: "bg-yellow-500"
  defp dot_color("critical"),   do: "bg-red-500 animate-pulse"
  defp dot_color(_),            do: "bg-gray-400"

  # --- Card de máquina ---

  attr :node, :map, required: true
  attr :flash, :boolean, default: false

  def machine_card(assigns) do
    ~H"""
    <div class={[
      "rounded-lg border p-4 transition-all duration-500",
      card_border(@node.status),
      @flash && "ring-2 ring-red-400 ring-offset-2 bg-red-50"
    ]}>
      <div class="flex items-center justify-between mb-3">
        <span class="font-mono text-sm font-semibold text-gray-700">
          <%= @node.node_id %>
        </span>
        <.status_badge status={@node.status} />
      </div>

      <div class="space-y-1 text-xs text-gray-500">
        <div class="flex justify-between">
          <span>Eventos processados</span>
          <span class="font-medium text-gray-700"><%= @node.event_count %></span>
        </div>
        <div class="flex justify-between">
          <span>Último pulso</span>
          <span class="font-medium text-gray-700"><%= format_ts(@node.timestamp) %></span>
        </div>
        <%= if is_map(@node.last_payload) do %>
          <div class="mt-2 pt-2 border-t border-gray-100">
            <div class="grid grid-cols-2 gap-y-1 gap-x-2 text-[10px] font-mono">
              <%= for {key, val} <- @node.last_payload do %>
                <span class="text-gray-400 capitalize truncate"><%= key %></span>
                <span class="text-right font-medium text-gray-700 truncate"><%= val %></span>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp card_border("ok"),       do: "border-green-200 bg-white"
  defp card_border("warning"),  do: "border-yellow-200 bg-white"
  defp card_border("critical"), do: "border-red-300 bg-red-50"
  defp card_border(_),          do: "border-gray-200 bg-white"

  defp format_ts(nil), do: "—"
  defp format_ts(ts) do
    ts
    |> DateTime.truncate(:second)
    |> Calendar.strftime("%H:%M:%S")
  end

  # --- Painel de estatísticas ---

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :color, :string, default: "gray"

  def stat_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-gray-200 bg-white p-4">
      <p class="text-xs text-gray-500 mb-1"><%= @label %></p>
      <p class={["text-2xl font-bold", stat_color(@color)]}>
        <%= @value %>
      </p>
    </div>
    """
  end

  defp stat_color("green"),  do: "text-green-600"
  defp stat_color("yellow"), do: "text-yellow-600"
  defp stat_color("red"),    do: "text-red-600"
  defp stat_color(_),        do: "text-gray-800"
end
