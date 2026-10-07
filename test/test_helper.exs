# Los schemas de institución que usan los tests se crean una sola vez, con
# una conexión real (ver Amauta.TenantMigrationsHelper). Los datos de cada
# test sí van dentro del sandbox.
Amauta.TenantMigrationsHelper.with_real_connection(fn ->
  for schema <- Amauta.Fixtures.tenant_schemas() do
    {:ok, _} = Amauta.Tenancy.Migrator.migrate_schema(schema)
  end
end)

# Se corren aparte:
#   * contra servicios reales (Garage): mix test --only integration
#   * en navegador (Playwright): bin/dev e2e (mix test --only e2e)
if System.get_env("E2E") == "1" do
  {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
  Application.put_env(:phoenix_test, :base_url, AmautaWeb.Endpoint.url())
end

ExUnit.start(exclude: [:integration, :e2e])
