defmodule AmautaWeb.Router do
  use AmautaWeb, :router

  import AmautaWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AmautaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # Resuelve la institución (modo ruta, ERS 8.4) y la persona de su sesión.
  pipeline :institution do
    plug AmautaWeb.Plugs.Tenant
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AmautaWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:amauta, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AmautaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Rutas de cada institución. Van al final porque el primer segmento es un
  # comodín; los slugs que chocan con rutas propias están reservados
  # (Amauta.Platform.Institution.reserved_slugs/0).
  scope "/:institution", AmautaWeb do
    pipe_through [:browser, :institution, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{AmautaWeb.UserAuth, :require_authenticated}] do
      live "/", HomeLive, :index
      live "/settings", UserLive.Settings, :edit
      live "/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/update-password", UserSessionController, :update_password
  end

  scope "/:institution", AmautaWeb do
    pipe_through [:browser, :institution]

    live_session :current_user,
      on_mount: [{AmautaWeb.UserAuth, :mount_current_scope}] do
      live "/log-in", UserLive.Login, :new
      live "/log-in/:token", UserLive.Confirmation, :new
    end

    post "/log-in", UserSessionController, :create
    delete "/log-out", UserSessionController, :delete
  end
end
