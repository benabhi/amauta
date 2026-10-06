defmodule Amauta.TenantMigrationsHelper do
  @moduledoc """
  Corre migraciones de institución en tests con una conexión real.

  En el sandbox, cada proceso trabaja dentro de una transacción que se
  revierte al terminar, y `Ecto.Migrator` ejecuta las migraciones en otro
  proceso: el DDL se perdería en silencio. Acá se toma una conexión sin
  sandbox y se comparte con los procesos que lance `fun`. Requiere
  `migration_lock: false` en el Repo de tests (config/test.exs).
  """
  alias Ecto.Adapters.SQL.Sandbox

  def with_real_connection(fun) do
    :ok = Sandbox.checkout(Amauta.Repo, sandbox: false)
    Sandbox.mode(Amauta.Repo, {:shared, self()})

    try do
      fun.()
    after
      Sandbox.checkin(Amauta.Repo)
      Sandbox.mode(Amauta.Repo, :manual)
    end
  end
end
