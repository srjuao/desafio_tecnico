defmodule WCore.Accounts.UserNotifier do
  @moduledoc """
  For sending user notification emails.

  In production you would use a real email delivery service.
  For now, we simply log the notification.
  """

  require Logger

  defp log_email(to, body) do
    Logger.debug("""
    ==============================
    EMAIL NOTIFICATION
    TO: #{to}
    ==============================
    #{body}
    ==============================
    """)
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    log_email(user.email, """
    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.
    """)

    {:ok, %{to: user.email}}
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    log_email(user.email, """
    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.
    """)

    {:ok, %{to: user.email}}
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    log_email(user.email, """
    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.
    """)

    {:ok, %{to: user.email}}
  end
end
