defmodule Amauta.Actions do
  @moduledoc "Catálogo y ejecución de acciones."
  alias Amauta.{Audit, Authorization, Repo, Scope}

  @actions [
    Amauta.Feed.Actions.ListPosts,
    Amauta.Feed.Actions.CreatePost
  ]

  @doc "Catálogo de acciones, listable en tiempo de ejecución."
  def all, do: @actions

  def run(action, %Scope{} = scope, params \\ %{}) do
    with {:ok, target} <- action.load(scope, params),
         :ok <- authorize(scope, action.permission(), target),
         {:ok, result} <- execute(action, scope, target, params) do
      action.after_commit(scope, target, result)
      {:ok, result}
    end
  end

  defp authorize(scope, permission, target) do
    if Authorization.can?(scope, permission, target), do: :ok, else: {:error, :forbidden}
  end

  defp execute(action, scope, target, params) do
    if action.audit?() do
      Repo.transact(fn ->
        with {:ok, result} <- action.execute(scope, target, params) do
          Audit.record!(scope, action.name(), result)
          {:ok, result}
        end
      end)
    else
      action.execute(scope, target, params)
    end
  end
end
