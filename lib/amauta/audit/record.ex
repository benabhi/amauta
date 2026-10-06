defmodule Amauta.Audit.Record do
  @moduledoc """
  Cambio reutilizable: registra un evento de auditoría en la misma
  transacción que la acción. El nombre del evento es
  `<dominio>.<recurso>.<acción>`, por ejemplo `feed.post.create`.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, result ->
      Amauta.Audit.Event
      |> Ash.Changeset.for_create(
        :create,
        %{
          actor_id: actor_id(context.actor),
          action: action_name(changeset),
          subject_type: changeset.resource |> Module.split() |> List.last(),
          subject_id: result.id
        },
        tenant: changeset.tenant,
        authorize?: false
      )
      |> Ash.create!()

      {:ok, result}
    end)
  end

  def action_name(%{resource: resource, action: action}) do
    [_app, domain, name] = resource |> Module.split() |> Enum.map(&Macro.underscore/1)
    "#{domain}.#{name}.#{action.name}"
  end

  defp actor_id(%Amauta.Scope{user: %{id: id}}), do: id
  defp actor_id(_), do: nil
end
