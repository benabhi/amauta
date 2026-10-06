# Los schemas de institución se crean una sola vez, fuera del sandbox:
# el DDL y las migraciones no pueden correr dentro de la transacción de cada
# test. Los datos de cada test sí van dentro del sandbox.
for schema <- Amauta.Fixtures.tenant_schemas() do
  Amauta.Tenancy.create_schema!(schema)
end

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Amauta.Repo, :manual)
