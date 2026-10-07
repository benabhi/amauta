import Config

# Los trabajos no se ejecutan solos en los tests: se verifican con Oban.Testing.
config :amauta, Oban, testing: :manual

# Almacenamiento en disco para los tests.
config :amauta, Amauta.Storage,
  adapter: Amauta.Storage.Local,
  root: Path.expand("../tmp/storage", __DIR__),
  bucket: "amauta-test"

# Partes chicas para probar la subida por partes sin archivos de megas.
config :amauta, Amauta.Files, single_max: 1024, part_size: 512

# El límite de intentos se prueba aparte (Amauta.Accounts.LoginThrottleTest).
config :amauta, Amauta.Accounts.LoginThrottle, enabled: false

# Only in tests, remove the complexity from the password hashing algorithm
config :argon2_elixir, t_cost: 1, m_cost: 8

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :amauta, Amauta.Repo,
  username: System.get_env("DATABASE_USER", "postgres"),
  password: System.get_env("DATABASE_PASSWORD", "postgres"),
  hostname: System.get_env("DATABASE_HOST", "localhost"),
  database: "amauta_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  # Sin lock de migración: los tests migran schemas con una única conexión
  # compartida (Amauta.TenantMigrationsHelper).
  migration_lock: false,
  pool_size: System.schedulers_online() * 2

# Las pruebas en navegador (mix test --only e2e) necesitan el servidor:
# el navegador corre en otro contenedor (Playwright) y entra por
# E2E_APP_HOST (en desarrollo, el contenedor «app»; en CI, localhost).
config :amauta, AmautaWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4002],
  url: [host: System.get_env("E2E_APP_HOST", "localhost"), port: 4002],
  secret_key_base: "w9bRJKeIlTIac9Sj42UgLIQffIuJTkbFh8ne/37Dq1uMLRImnI2T7K9hI0FMpS6l",
  server: true

# Los pedidos del navegador comparten la transacción del test (sandbox).
config :amauta, :sql_sandbox, true

# Pruebas en navegador con Playwright, contra un servidor remoto (ver
# compose.yaml, perfil «e2e», y .github/workflows/ci.yml).
config :phoenix_test,
  otp_app: :amauta,
  endpoint: AmautaWeb.Endpoint,
  playwright: [
    ws_endpoint: System.get_env("PLAYWRIGHT_WS_ENDPOINT", "ws://localhost:3000"),
    browser_pool: false,
    timeout: 5_000
  ]

# In test we don't send emails
config :amauta, Amauta.Mailer, adapter: Swoosh.Adapters.Test

# Los emails pasan por el mismo camino que en producción, pero salen en el
# momento (sin la cola), así los tests los reciben enseguida.
config :amauta, Amauta.Mail, inline: true, rate_limits: []
config :amauta, Amauta.Notifications, email_window: 0

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Inicio de sesión rápido con las personas de ejemplo (RNF-DEV-009).
config :amauta, dev_login: true
