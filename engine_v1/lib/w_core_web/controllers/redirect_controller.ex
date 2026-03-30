defmodule WCoreWeb.RedirectController do
  use WCoreWeb, :controller

  def to_dashboard(conn, _params) do
    redirect(conn, to: ~p"/dashboard")
  end
end
