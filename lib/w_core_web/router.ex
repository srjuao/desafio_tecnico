defmodule WCoreWeb.Router do
  use WCoreWeb, :router

  import WCoreWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WCoreWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Public routes
  scope "/", WCoreWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Auth routes (redirect if already authenticated)
  scope "/", WCoreWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{WCoreWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log-in", UserLoginLive, :new
    end

    post "/users/log-in", UserSessionController, :create
  end

  # Protected routes (require authentication)
  scope "/", WCoreWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{WCoreWeb.UserAuth, :ensure_authenticated}] do
      live "/dashboard", DashboardLive, :index
      live "/users/settings", UserSettingsLive, :edit
    end
  end

  # Logout
  scope "/", WCoreWeb do
    pipe_through :browser

    delete "/users/log-out", UserSessionController, :delete
  end

  # API routes
  # scope "/api", WCoreWeb do
  #   pipe_through :api
  # end
end
