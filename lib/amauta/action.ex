defmodule Amauta.Action do
  @moduledoc """
  Una acción del dominio (ERS 8.2): la única puerta para modificar datos.
  La interfaz, la API y los trabajos en segundo plano invocan las mismas
  acciones con `Amauta.Actions.run/3`, así comparten validación,
  autorización, auditoría y efectos.

  ## Declaración

      defmodule Amauta.Feed.Actions.CreatePost do
        use Amauta.Action,
          name: "feed.post.create",
          description: "Publica en el tablón de un curso.",
          params: [
            course_id: {Ecto.UUID, required: true},
            body: {:string, required: true}
          ]

        @impl true
        def authorize(scope, input), do: ...

        @impl true
        def run(scope, input), do: ...
      end

  El nombre es estable (se usa en la auditoría, la API y el catálogo). Los
  parámetros son tipos de Ecto; `required: true` los vuelve obligatorios y
  `sensitive: true` los deja fuera de la auditoría.

  ## Recorrido

    1. `validate/1` sobre el changeset de los parámetros (opcional).
    2. `authorize/2`: `:ok`, `{:error, :forbidden}` o `{:error, :not_found}`.
    3. `run/2` dentro de una transacción, junto con el registro de auditoría.
    4. `after_commit/3`, solo si la transacción se confirmó.
  """
  alias Amauta.Scope

  @type input :: %{atom() => term()}
  @type param_spec :: {atom() | module(), keyword()}

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback params() :: [{atom(), param_spec()}]
  @callback validate(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  @callback authorize(Scope.t(), input()) :: :ok | {:error, :forbidden | :not_found}
  @callback run(Scope.t(), input()) :: {:ok, term()} | {:error, term()}
  @callback audit(Scope.t(), input(), result :: term()) :: {struct() | nil, map()} | :skip
  @callback after_commit(Scope.t(), input(), result :: term()) :: :ok

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.fetch!(opts, :description)
    params = Keyword.get(opts, :params, [])

    quote do
      @behaviour Amauta.Action

      @impl true
      def name, do: unquote(name)

      @impl true
      def description, do: unquote(description)

      @impl true
      def params do
        Enum.map(unquote(params), fn
          {field, {type, opts}} -> {field, {type, opts}}
          {field, type} -> {field, {type, []}}
        end)
      end

      @impl true
      def validate(changeset), do: changeset

      @impl true
      def audit(_scope, input, result), do: Amauta.Action.default_audit(__MODULE__, input, result)

      @impl true
      def after_commit(_scope, _input, _result), do: :ok

      defoverridable validate: 1, audit: 3, after_commit: 3
    end
  end

  @doc """
  Auditoría por defecto: el sujeto es el resultado (si es un struct con ID)
  y los metadatos son los parámetros, sin los sensibles.
  """
  def default_audit(action, input, result) do
    sensitive = for {field, {_type, opts}} <- action.params(), opts[:sensitive], do: field
    subject = if is_struct(result) and Map.has_key?(result, :id), do: result
    {subject, Map.drop(input, sensitive)}
  end
end
