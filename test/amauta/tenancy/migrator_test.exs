defmodule Amauta.Tenancy.MigratorTest do
  @moduledoc "Alta de instituciones y migraciones por schema (RF-ADM-002 y RF-ADM-006)."
  #
  # Ecto.Migrator no puede correr dentro del sandbox (ver
  # Amauta.TenantMigrationsHelper), así que estos tests usan una conexión
  # real y limpian lo que crean. Son sincrónicos: ExUnit los corre cuando ya
  # terminaron los tests en paralelo, así que el modo compartido no afecta a
  # otros.
  use ExUnit.Case, async: false

  import Amauta.DataCase, only: [errors_on: 1]
  import Ecto.Query

  alias Amauta.{Audit, Repo, Tenancy}
  alias Amauta.Platform.Institution
  alias Amauta.Tenancy.Migrator
  alias Ecto.Adapters.SQL.Sandbox

  @latest Migrator.migrations() |> List.last() |> elem(0)
  @slugs ~w(unsur sana rota)

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    Sandbox.mode(Repo, {:shared, self()})
    # Por si una corrida anterior se interrumpió antes de limpiar.
    cleanup()
    on_exit(fn -> Amauta.TenantMigrationsHelper.with_real_connection(&cleanup/0) end)
  end

  defp cleanup do
    institutions = Repo.all(from(i in Institution, where: i.slug in @slugs))

    for %{schema_name: schema} <- institutions do
      Repo.query!(~s(DROP SCHEMA IF EXISTS "#{schema}" CASCADE))
    end

    Repo.query!(~s(DROP SCHEMA IF EXISTS "inst_broken" CASCADE))
    Repo.delete_all(from(i in Institution, where: i.slug in @slugs))
  end

  test "el alta crea el schema, lo migra y registra la versión" do
    assert {:ok, %Institution{} = institution} =
             Tenancy.create_institution(%{slug: "unsur", name: "Universidad del Sur"})

    assert institution.schema_name =~ ~r/^inst_[a-z0-9]{10}$/
    assert institution.schema_version == @latest
    assert institution.migration_error == nil
    assert %DateTime{} = institution.migrated_at

    # El schema nuevo ya se puede usar.
    Audit.record!(institution, "test.created")
    assert [_] = Audit.list_events(institution)
  end

  test "el alta valida los datos antes de crear el schema" do
    assert {:error, changeset} = Tenancy.create_institution(%{slug: "api", name: "X"})
    assert "is reserved" in errors_on(changeset).slug
  end

  test "un fallo en una institución no bloquea a las demás y queda registrado" do
    {:ok, healthy} = Tenancy.create_institution(%{slug: "sana", name: "Sana"})

    # Un schema con una tabla que choca con la primera migración.
    broken =
      %Institution{}
      |> Institution.changeset(%{slug: "rota", name: "Rota"})
      |> Ecto.Changeset.put_change(:schema_name, "inst_broken")
      |> Repo.insert!()

    Repo.query!(~s(CREATE SCHEMA "inst_broken"))
    Repo.query!(~s|CREATE TABLE "inst_broken"."audit_events" (id uuid)|)

    results = Map.new(Migrator.migrate_all(concurrency: 2), fn {i, r} -> {i.slug, r} end)

    assert {:ok, @latest} = results["sana"]
    assert {:error, message} = results["rota"]
    assert message =~ "already exists"

    assert %{migration_error: nil, schema_version: @latest} = Repo.reload!(healthy)
    assert %{migration_error: error, schema_version: nil} = Repo.reload!(broken)
    assert error =~ "already exists"
  end

  test "varios procesos cargan las migraciones a la vez sin compilar dos veces" do
    for file <- Path.wildcard(Path.join(Migrator.migrations_path(), "*.exs")) do
      :persistent_term.erase({Migrator, file})
    end

    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      results =
        1..8
        |> Task.async_stream(fn _ -> Migrator.migrations() end, max_concurrency: 8)
        |> Enum.map(fn {:ok, migrations} -> migrations end)

      assert [Migrator.migrations()] == Enum.uniq(results)
    after
      Code.put_compiler_option(:ignore_module_conflict, false)
    end
  end

  test "migrar un schema al día no hace nada" do
    assert {:ok, @latest} = Migrator.migrate_schema("inst_test_a")
    assert {:ok, @latest} = Migrator.migrate_schema("inst_test_a")
  end

  test "rechaza nombres de schema inválidos" do
    assert {:error, message} = Migrator.migrate_schema(~s(inst_a"; DROP SCHEMA global; --))
    assert message =~ "invalid institution schema name"
  end
end
