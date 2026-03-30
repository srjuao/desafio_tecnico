defmodule WCoreWeb.UserSettingsLive do
  use WCoreWeb, :live_view

  alias WCore.Accounts

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header class="text-center">
        Configuracoes da Conta
        <:subtitle>Gerencie seu email e senha</:subtitle>
      </.header>

      <div class="space-y-12 divide-y divide-base-300">
        <div>
          <.simple_form
            for={@email_form}
            id="email_form"
            phx-submit="update_email"
            phx-change="validate_email"
          >
            <.input field={@email_form[:email]} type="email" label="Email" required />
            <.input
              field={@email_form[:current_password]}
              name="current_password"
              id="current_password_for_email"
              type="password"
              label="Senha atual"
              value={@email_form_current_password}
              required
            />
            <:actions>
              <.button phx-disable-with="Alterando...">Alterar Email</.button>
            </:actions>
          </.simple_form>
        </div>

        <div>
          <.simple_form
            for={@password_form}
            id="password_form"
            action={~p"/users/log-in?_action=password_updated"}
            method="post"
            phx-change="validate_password"
            phx-submit="update_password"
            phx-trigger-action={@trigger_submit}
          >
            <input
              name={@password_form[:email].name}
              type="hidden"
              id="hidden_user_email"
              value={@current_email}
            />
            <.input field={@password_form[:password]} type="password" label="Nova senha" required />
            <.input
              field={@password_form[:password_confirmation]}
              type="password"
              label="Confirmar nova senha"
            />
            <.input
              field={@password_form[:current_password]}
              name="current_password"
              type="password"
              label="Senha atual"
              id="current_password_for_password"
              value={@current_password}
              required
            />
            <:actions>
              <.button phx-disable-with="Alterando...">Alterar Senha</.button>
            </:actions>
          </.simple_form>
        </div>
      </div>
    </Layouts.app>
    """
  end


  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    email_changeset = Accounts.change_user_email(user)
    password_changeset = Accounts.change_user_password(user)

    socket =
      socket
      |> assign(:current_password, nil)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset, as: "user"))
      |> assign(:password_form, to_form(password_changeset, as: "user"))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  def handle_event("validate_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    email_form =
      socket.assigns.current_user
      |> Accounts.change_user_email(user_params)
      |> Map.put(:action, :validate)
      |> to_form(as: "user")

    {:noreply, assign(socket, email_form: email_form, email_form_current_password: password)}
  end

  def handle_event("update_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} ->
        {:noreply, put_flash(socket, :info, "Um link de confirmacao foi enviado para o novo email.")}

      changeset ->
        {:noreply, assign(socket, email_form: to_form(Map.put(changeset, :action, :insert), as: "user"))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)
      |> to_form(as: "user")

    {:noreply, assign(socket, password_form: password_form, current_password: password)}
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        password_form =
          user
          |> Accounts.change_user_password(user_params)
          |> to_form(as: "user")

        {:noreply, assign(socket, trigger_submit: true, password_form: password_form)}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset, as: "user"))}
    end
  end
end
