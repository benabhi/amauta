defmodule AmautaWeb.Router do
  use AmautaWeb, :router

  # En los tests en navegador, cada LiveView usa la transacción del test
  # (AmautaWeb.SandboxHook); tiene que ir antes que los demás on_mount.
  @sandbox if Application.compile_env(:amauta, :sql_sandbox),
             do: [AmautaWeb.SandboxHook],
             else: []

  import AmautaWeb.UserAuth
  import AmautaWeb.StaffAuth
  import Phoenix.LiveDashboard.Router

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
    plug AmautaWeb.Locale
  end

  # Personal de plataforma (/admin).
  pipeline :staff do
    plug :fetch_current_staff
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AmautaWeb do
    pipe_through [:browser, :redirect_to_setup]

    get "/", PageController, :home
  end

  # Asistente de primera ejecución (RF-ADM-001).
  scope "/", AmautaWeb do
    pipe_through :browser

    live "/setup", SetupLive
  end

  # Administración de la instancia.
  scope "/admin", AmautaWeb.Admin do
    pipe_through [:browser, :staff]

    get "/log-in", SessionController, :new
    post "/log-in", SessionController, :create
    delete "/log-out", SessionController, :delete
  end

  scope "/admin", AmautaWeb.Admin do
    pipe_through [:browser, :staff, :require_staff]

    live_session :staff, on_mount: @sandbox ++ [{AmautaWeb.StaffAuth, :require_staff}] do
      live "/", InstitutionsLive, :index
      live "/institutions/new", InstitutionsLive, :new
      live "/institutions/:id", InstitutionLive, :show
    end
  end

  # Telemetría, solo para la superadministración (RNF-OBS-004).
  scope "/admin" do
    pipe_through [:browser, :staff, :require_staff]

    live_dashboard "/dashboard",
      metrics: AmautaWeb.Telemetry,
      on_mount: [{AmautaWeb.StaffAuth, :require_staff}]
  end

  # Vista previa de correos y catálogo de componentes, solo en desarrollo.
  if Application.compile_env(:amauta, :dev_routes) do
    require AmautaWeb.StorybookRoutes

    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    # Catálogo vivo de componentes (ERS 6.5.7).
    AmautaWeb.StorybookRoutes.routes()
  end

  # Rutas de cada institución. Van al final porque el primer segmento es un
  # comodín; los slugs que chocan con rutas propias están reservados
  # (Amauta.Platform.Institution.reserved_slugs/0).
  scope "/:institution", AmautaWeb do
    pipe_through [:browser, :institution, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: @sandbox ++ [{AmautaWeb.UserAuth, :require_authenticated}, AmautaWeb.Locale] do
      live "/", HomeLive, :index
      live "/settings", UserLive.Settings, :edit
      live "/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/people", PeopleLive, :index
      live "/people/new", PeopleLive, :new
      live "/people/import", PeopleImportLive
      live "/people/:id/edit", PeopleLive, :edit
      live "/periods", PeriodsLive, :index
      live "/periods/new", PeriodsLive, :new
      live "/periods/:id/edit", PeriodsLive, :edit
      live "/pathways", PathwaysLive, :index
      live "/pathways/new", PathwaysLive, :new
      live "/pathways/:slug", PathwayLive, :show
      live "/pathways/:slug/edit", PathwayLive, :edit
      live "/pathways/:slug/enroll", PathwayEnrollLive
      live "/courses", CoursesLive, :index
      live "/courses/new", CoursesLive, :new
      live "/c/:slug", CourseLive, :feed
      live "/c/:slug/content", CourseLive, :content
      live "/c/:slug/people", CourseLive, :people
      live "/c/:slug/grades", CourseLive, :grades
      live "/c/:slug/settings", CourseLive, :settings
      live "/c/:slug/people/import", CourseImportLive
      live "/join", JoinLive
    end

    get "/people/export", PeopleExportController, :export
    get "/files/:id", FileController, :show
    post "/update-password", UserSessionController, :update_password
  end

  scope "/:institution", AmautaWeb do
    pipe_through [:browser, :institution]

    live_session :current_user,
      on_mount: @sandbox ++ [{AmautaWeb.UserAuth, :mount_current_scope}, AmautaWeb.Locale] do
      live "/log-in", UserLive.Login, :new
      live "/log-in/:token", UserLive.Confirmation, :new
    end

    post "/log-in", UserSessionController, :create
    delete "/log-out", UserSessionController, :delete

    # Inicio de sesión rápido por rol, solo en desarrollo (RNF-DEV-009).
    if Application.compile_env(:amauta, :dev_login, false) do
      get "/dev/login", DevLoginController, :index
      post "/dev/login/:user_id", DevLoginController, :create
    end
  end
end
