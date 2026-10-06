defmodule AmautaWeb.Router do
  use AmautaWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AmautaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :tenant do
    plug AmautaWeb.Plugs.Tenant
  end

  # La institución sale del token, no de la URL. Las rutas y la
  # especificación OpenAPI las genera AshJsonApi desde los recursos.
  scope "/api/v1" do
    pipe_through [:api, AmautaWeb.Plugs.ApiAuth]

    forward "/", AmautaWeb.AshJsonApiRouter
  end

  scope "/", AmautaWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", AmautaWeb do
  #   pipe_through :api
  # end

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

  # Rutas de cada institución en modo ruta (ERS 8.4). Van al final porque
  # el primer segmento es un comodín.
  scope "/:institution", AmautaWeb do
    pipe_through [:browser, :tenant]

    if Application.compile_env(:amauta, :dev_login, false) do
      get "/dev/login/:user_id", DevLoginController, :create
    end

    live_session :tenant, on_mount: AmautaWeb.ScopeHook do
      live "/c/:course/feed", FeedLive
    end
  end
end
