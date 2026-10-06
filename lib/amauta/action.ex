defmodule Amauta.Action do
  @moduledoc """
  Capa de acciones (ERS 8.2): la única puerta al dominio para la interfaz,
  la API y los trabajos. Cada acción declara su nombre estable y su
  permiso; `Amauta.Actions.run/3` aplica siempre el mismo recorrido:

    1. carga el objetivo dentro de la institución (`load/2`),
    2. autoriza con el Scope,
    3. ejecuta en una transacción (`execute/3`) y audita,
    4. emite los efectos después de confirmar (`after_commit/3`).
  """
  alias Amauta.Scope

  @callback name() :: String.t()
  @callback permission() :: String.t()
  @callback audit?() :: boolean()
  @callback load(Scope.t(), map()) :: {:ok, target :: struct()} | {:error, :not_found}
  @callback execute(Scope.t(), target :: struct(), map()) :: {:ok, term()} | {:error, term()}
  @callback after_commit(Scope.t(), target :: struct(), result :: term()) :: :ok

  defmacro __using__(opts) do
    quote do
      @behaviour Amauta.Action
      @impl true
      def name, do: unquote(Keyword.fetch!(opts, :name))
      @impl true
      def permission, do: unquote(Keyword.fetch!(opts, :permission))
      @impl true
      def audit?, do: unquote(Keyword.get(opts, :audit, true))
      @impl true
      def after_commit(_scope, _target, _result), do: :ok
      defoverridable after_commit: 3
    end
  end
end
