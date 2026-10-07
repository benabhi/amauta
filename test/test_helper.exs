# Los schemas de institución que usan los tests se crean una sola vez, con
# una conexión real (ver Amauta.TenantMigrationsHelper). Los datos de cada
# test sí van dentro del sandbox.
Amauta.TenantMigrationsHelper.with_real_connection(fn ->
  for schema <- Amauta.Fixtures.tenant_schemas() do
    {:ok, _} = Amauta.Tenancy.Migrator.migrate_schema(schema)
  end
end)

# Las pruebas contra servicios reales (Garage) se corren aparte:
# mix test --only integration
ExUnit.start(exclude: [:integration])
