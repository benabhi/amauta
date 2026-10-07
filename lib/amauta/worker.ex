defmodule Amauta.Worker do
  @moduledoc """
  Base de los trabajos en segundo plano que operan sobre una institución
  (ERS 8.9). La tabla de Oban es global, así que cada trabajo lleva
  `"institution_id"` en sus argumentos; este módulo lo resuelve y llama a
  `perform_for/2` con la institución.

      defmodule Amauta.Audit.VerifyWorker do
        use Amauta.Worker, queue: :maintenance

        @impl Amauta.Worker
        def perform_for(institution, _args), do: ...
      end

      Amauta.Audit.VerifyWorker.new_for(institution, %{})
  """
  alias Amauta.Platform.Institution

  @callback perform_for(Institution.t(), map()) :: Oban.Worker.result()

  defmacro __using__(opts) do
    quote do
      use Oban.Worker, unquote(opts)
      @behaviour Amauta.Worker

      @doc "Changeset del trabajo para una institución (o un Scope)."
      def new_for(tenant, args \\ %{}, opts \\ []) do
        args
        |> Map.put("institution_id", Amauta.Worker.institution_id(tenant))
        |> new(opts)
      end

      @impl Oban.Worker
      def perform(%Oban.Job{args: %{"institution_id" => id} = args}) do
        case Amauta.Repo.get(Amauta.Platform.Institution, id) do
          nil -> {:cancel, :institution_not_found}
          institution -> perform_for(institution, Map.delete(args, "institution_id"))
        end
      end
    end
  end

  @doc false
  def institution_id(%Institution{id: id}), do: id
  def institution_id(%{institution: %Institution{id: id}}), do: id
end
