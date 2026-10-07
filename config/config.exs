# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :amauta, :scopes,
  user: [
    default: true,
    module: Amauta.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: Amauta.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :amauta,
  ecto_repos: [Amauta.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configure the endpoint
config :amauta, AmautaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AmautaWeb.ErrorHTML, json: AmautaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Amauta.PubSub,
  live_view: [signing_salt: "AVaiF0Xn"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Formatos locales (ver Amauta.Cldr).
config :ex_cldr, default_backend: Amauta.Cldr

# Zonas horarias con la base IANA incluida en el paquete. Sin actualización
# automática: Amauta no depende de la red en tiempo de ejecución (P4).
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase
config :tzdata, :autoupdate, :disabled

# URL del enlace mágico para los emails que arma el dominio (invitaciones).
config :amauta, :login_url, {AmautaWeb.Paths, :absolute_log_in}

# Si el WebSocket no conecta en este tiempo, LiveView pasa a long-poll y lo
# recuerda por la sesión del navegador. `nil` lo desactiva (desarrollo).
config :amauta, :longpoll_fallback_ms, 2500

# Remitente de los emails de la plataforma. El remitente por institución
# (RF-INS-012) llega con su configuración.
config :amauta, :mail_from, {"Amauta", "no-responder@amauta.localhost"}

# Trabajos en segundo plano (ERS 8.9). La tabla vive en el schema global y
# cada trabajo indica su institución en los argumentos.
config :amauta, Oban,
  engine: Oban.Engines.Basic,
  repo: Amauta.Repo,
  prefix: "global",
  queues: [
    deadlines: 20,
    notifications: 20,
    mailers: 10,
    default: 10,
    webhooks: 10,
    media: 4,
    certificates: 4,
    exports: 2,
    imports: 2,
    maintenance: 1
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 60 * 60},
    {Oban.Plugins.Cron, crontab: [{"30 3 * * *", Amauta.Audit.VerifyAllWorker}]}
  ]

# Almacenamiento compatible con S3 (ERS 8.10). En desarrollo, Garage; las
# credenciales y el endpoint se leen del entorno en config/runtime.exs.
config :amauta, Amauta.Storage, adapter: Amauta.Storage.S3

# Límites de archivos de la instancia (RF-ARC-003): tamaño máximo y tipos
# permitidos. Cada propósito puede ser más estricto
# (Amauta.Files.Purpose); las cuotas por institución y curso llegan en V1.
config :amauta, Amauta.Files,
  max_size: 500 * 1024 * 1024,
  allowed_types: ~w(
    application/pdf image/png image/jpeg image/gif image/webp video/mp4 audio/mp4 audio/mpeg
    application/zip text/plain text/csv text/markdown
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    application/vnd.openxmlformats-officedocument.presentationml.presentation
    application/vnd.oasis.opendocument.text application/vnd.oasis.opendocument.spreadsheet
    application/vnd.oasis.opendocument.presentation
    application/msword application/vnd.ms-excel application/vnd.ms-powerpoint
  )

config :ex_aws, http_client: ExAws.Request.Req, json_codec: Jason

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :amauta, Amauta.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  # app.js es un módulo ES con división de código: las piezas pesadas (el
  # editor de bloques, KaTeX, el resaltado de código) se cargan bajo demanda
  # con import() (ERS 8.x, sección de JavaScript).
  amauta: [
    args:
      ~w(js/app.js --bundle --splitting --format=esm --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ],
  storybook: [
    args:
      ~w(js/storybook.js --bundle --target=es2022 --outdir=../priv/static/assets/js --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  amauta: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
