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
    plug OpenApiSpex.Plug.PutApiSpec, module: AmautaWeb.ApiSpec
  end

  pipeline :api_auth do
    plug AmautaWeb.Plugs.ApiAuth
  end

  pipeline :tenant do
    plug AmautaWeb.Plugs.Tenant
  end

  scope "/", AmautaWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/api/v1" do
    pipe_through :api

    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
  end

  # La institución sale del token, no de la URL.
  scope "/api/v1", AmautaWeb.Api do
    pipe_through [:api, :api_auth]

    get "/courses/:course_id/posts", PostController, :index
    post "/courses/:course_id/posts", PostController, :create
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
