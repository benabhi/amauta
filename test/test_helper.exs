# Los schemas de institución se crean una sola vez, fuera del sandbox:
# el DDL y las migraciones no pueden correr dentro de la transacción de cada
# test. Los datos de cada test sí van dentro del sandbox.
Code.put_compiler_option(:ignore_module_conflict, true)

for schema <- Amauta.Fixtures.tenant_schemas() do
  Amauta.Repo.query!(~s(CREATE SCHEMA IF NOT EXISTS "#{schema}"))
  path = Application.app_dir(:amauta, "priv/repo/tenant_migrations")
  Ecto.Migrator.run(Amauta.Repo, path, :up, all: true, prefix: schema, log: false)
end

Code.put_compiler_option(:ignore_module_conflict, false)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Amauta.Repo, :manual)
