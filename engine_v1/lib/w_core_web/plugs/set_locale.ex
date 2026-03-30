defmodule WCoreWeb.Plugs.SetLocale do
  @moduledoc """
  Plug para gerenciar o idioma (locale) do usuário.
  Verifica params["locale"] ou a sessão e define Gettext.put_locale.
  """
  import Plug.Conn

  @whitelist ["en", "pt_BR", "es"]
  @default "en"

  def init(_opts), do: nil

  def call(conn, _opts) do
    locale = fetch_locale(conn)
    Gettext.put_locale(WCoreWeb.Gettext, locale)

    conn
    |> put_session(:locale, locale)
    |> assign(:locale, locale)
  end

  defp fetch_locale(conn) do
    locale = conn.params["locale"] || get_session(conn, :locale)

    if locale in @whitelist do
      locale
    else
      @default
    end
  end
end
