defmodule Amauta.Audit do
  @moduledoc "Auditoría por institución."
  import Ecto.Query
  alias Amauta.Audit.Event
  alias Amauta.{Repo, Tenancy}

  def record!(scope, action, subject, metadata \\ %{}) do
    Repo.insert!(
      %Event{
        actor_id: scope.user && scope.user.id,
        action: action,
        subject_type: subject.__struct__ |> Module.split() |> List.last(),
        subject_id: subject.id,
        metadata: metadata
      },
      Tenancy.opts(scope)
    )
  end

  def list_events(tenant) do
    Repo.all(from(e in Event, order_by: [asc: e.inserted_at]), Tenancy.opts(tenant))
  end
end
