defmodule WCore.Accounts.UserNotifier do
  require Logger

  alias WCore.Accounts.User

  # Delivers the email using Logger (no Swoosh)
  defp deliver(recipient, subject, body) do
    Logger.info("""

    [USER NOTIFIER]
    To: #{recipient}
    Subject: #{subject}
    Body:
    #{body}
    """)
    {:ok, %{recipient: recipient, subject: subject, text_body: body}}
  end

  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """
    Hi #{user.email},
    You can change your email by visiting the URL below:
    #{url}
    """)
  end

  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Log in instructions", """
    Hi #{user.email},
    You can log into your account by visiting the URL below:
    #{url}
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """
    Hi #{user.email},
    You can confirm your account by visiting the URL below:
    #{url}
    """)
  end
end
