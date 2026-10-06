defmodule Mix.Tasks.Amauta.Migrate do
  @shortdoc "Migra el schema global y los de todas las instituciones"
  @moduledoc """
  Aplica las migraciones globales y después las de cada institución, en
  paralelo (RF-ADM-006). Informa el resultado por institución y termina con
  error si alguna falló; las demás quedan migradas.

      mix amauta.migrate
      mix amauta.migrate --concurrency 8
      mix amauta.migrate --quiet
  """
  use Mix.Task

  alias Amauta.Tenancy.Migrator

  @switches [concurrency: :integer, quiet: :boolean]

  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches)

    Mix.Task.run("ecto.migrate", if(opts[:quiet], do: ["--quiet"], else: []))
    Mix.Task.run("app.config")

    {:ok, results, _} =
      Ecto.Migrator.with_repo(Amauta.Repo, fn _repo ->
        Migrator.migrate_all(Keyword.take(opts, [:concurrency]))
      end)

    failed = for {institution, {:error, message}} <- results, do: {institution, message}

    if !opts[:quiet] do
      Mix.shell().info(
        "Instituciones migradas: #{length(results) - length(failed)}/#{length(results)}"
      )
    end

    for {institution, message} <- failed do
      Mix.shell().error("  #{institution.slug} (#{institution.schema_name}): #{message}")
    end

    if failed != [], do: Mix.raise("#{length(failed)} institution(s) failed to migrate")
  end
end
