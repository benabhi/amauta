defmodule Amauta.Actions do
  @moduledoc """
  Catálogo y ejecución de las acciones del dominio (ver `Amauta.Action`).

  El catálogo se puede listar en tiempo de ejecución: de ahí salen la
  paridad de la API (RF-API-001), el explicador de permisos y la
  documentación.
  """
  import Ecto.Changeset

  alias Amauta.{Audit, Repo, Scope}

  @actions [
    Amauta.Accounts.Actions.CreateUser,
    Amauta.Accounts.Actions.UpdateUser,
    Amauta.Accounts.Actions.SuspendUser,
    Amauta.Accounts.Actions.ReactivateUser,
    Amauta.Accounts.Actions.ResendInvitation,
    Amauta.Accounts.Actions.ImportUsers,
    Amauta.Accounts.Actions.ExportUsers,
    Amauta.Authorization.Actions.AssignRole,
    Amauta.Authorization.Actions.RevokeRole
  ]

  @doc "Todas las acciones."
  @spec all() :: [module()]
  def all, do: @actions

  @doc "Acción por nombre, o `nil`."
  @spec get(String.t()) :: module() | nil
  def get(name), do: Enum.find(@actions, &(&1.name() == name))

  @doc """
  Ejecuta una acción. Devuelve `{:ok, resultado}`, `{:error, changeset}`
  si los parámetros no son válidos, `{:error, :forbidden}`,
  `{:error, :not_found}` o el error que devuelva la acción.
  """
  @spec run(module(), Scope.t(), map()) :: {:ok, term()} | {:error, term()}
  def run(action, %Scope{} = scope, params \\ %{}) do
    metadata = %{action: action.name(), institution_id: scope.institution.id}

    :telemetry.span([:amauta, :action], metadata, fn ->
      result = do_run(action, scope, params)
      {result, Map.put(metadata, :status, status(result))}
    end)
  end

  defp do_run(action, scope, params) do
    with {:ok, input} <- cast(action, params),
         :ok <- action.authorize(scope, input),
         {:ok, result} <- transact(action, scope, input) do
      action.after_commit(scope, input, result)
      {:ok, result}
    end
  end

  @doc "Valida los parámetros de una acción contra su declaración."
  @spec cast(module(), map()) :: {:ok, Amauta.Action.input()} | {:error, Ecto.Changeset.t()}
  def cast(action, params) do
    specs = action.params()
    types = Map.new(specs, fn {field, {type, _opts}} -> {field, type} end)
    required = for {field, {_type, opts}} <- specs, opts[:required], do: field

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> validate_required(required)
    |> action.validate()
    |> apply_action(:run)
  end

  defp transact(action, scope, input) do
    Repo.transact(fn ->
      with {:ok, result} <- action.run(scope, input) do
        record_audit(action, scope, input, result)
        enqueue_effects(action, scope, input, result)
        {:ok, result}
      end
    end)
  end

  # Los trabajos se insertan en la misma transacción que el cambio
  # (ERS 8.2): nunca se pierden por una caída justo después del commit.
  defp enqueue_effects(action, scope, input, result) do
    case action.effects(scope, input, result) do
      [] -> :ok
      jobs -> Oban.insert_all(jobs)
    end
  end

  defp record_audit(action, scope, input, result) do
    case action.audit(scope, input, result) do
      :skip ->
        :ok

      {subject, metadata} ->
        Audit.record!(scope, action.name(),
          actor_id: scope.user && scope.user.id,
          subject: subject,
          metadata: metadata
        )
    end
  end

  defp status({:ok, _}), do: :ok
  defp status({:error, %Ecto.Changeset{}}), do: :invalid
  defp status({:error, reason}) when is_atom(reason), do: reason
  defp status({:error, _}), do: :error
end
