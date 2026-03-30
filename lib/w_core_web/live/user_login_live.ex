defmodule WCoreWeb.UserLoginLive do
  use WCoreWeb, :live_view

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={assigns[:current_user]}>
      <div class="mx-auto max-w-sm">
        <.header class="text-center">
          Entrar
          <:subtitle>
            Nao tem conta?
            <.link navigate={~p"/users/register"} class="font-semibold text-primary hover:underline">
              Registre-se
            </.link>
          </:subtitle>
        </.header>

        <.simple_form for={@form} id="login_form" action={~p"/users/log-in"} phx-update="ignore">
          <.input field={@form[:email]} type="email" label="Email" required />
          <.input field={@form[:password]} type="password" label="Senha" required />

          <:actions>
            <.input field={@form[:remember_me]} type="checkbox" label="Lembrar de mim" />
          </:actions>
          <:actions>
            <.button phx-disable-with="Entrando..." class="w-full btn-primary">
              Entrar <span aria-hidden="true">&rarr;</span>
            </.button>
          </:actions>
        </.simple_form>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
