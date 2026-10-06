defmodule Amauta.Pathways.Actions.Helpers do
  @moduledoc false
  alias Amauta.Pathways.Pathway
  alias Amauta.{Authorization, Pathways, Repo, Tenancy}

  @doc "Verifica el permiso sobre el trayecto; si no existe, `:not_found`."
  def authorize_pathway(scope, id, permission) do
    case Pathways.get(scope, id) do
      nil -> {:error, :not_found}
      pathway -> Authorization.authorize(scope, permission, pathway)
    end
  end

  @doc "Verifica el permiso sobre el trayecto de la etapa."
  def authorize_stage(scope, id, permission) do
    case Pathways.get_stage(scope, id) do
      nil -> {:error, :not_found}
      stage -> Authorization.authorize(scope, permission, stage.pathway)
    end
  end

  def fetch_pathway(scope, id) do
    case Pathways.get(scope, id) do
      nil -> {:error, :not_found}
      pathway -> {:ok, pathway}
    end
  end

  def fetch_stage(scope, id) do
    case Pathways.get_stage(scope, id) do
      nil -> {:error, :not_found}
      %{pathway: %{status: "archived"}} -> {:error, :archived}
      stage -> {:ok, stage}
    end
  end

  @doc "Trayecto que se puede modificar: uno archivado es de solo lectura."
  def fetch_editable_pathway(scope, id) do
    case fetch_pathway(scope, id) do
      {:ok, %{status: "archived"}} -> {:error, :archived}
      result -> result
    end
  end

  @doc "Cambia el estado si la transición es válida (ERS 4.8)."
  def transition(scope, id, from, to) do
    with {:ok, pathway} <- fetch_pathway(scope, id) do
      if pathway.status in from do
        pathway |> Pathway.status_changeset(to) |> Repo.update(Tenancy.opts(scope))
      else
        {:error, :invalid_transition}
      end
    end
  end
end

defmodule Amauta.Pathways.Actions.CreatePathway do
  @moduledoc "Crea un trayecto en borrador (RF-TRA-001)."
  use Amauta.Action,
    name: "pathways.pathway.create",
    description: "Crea un trayecto.",
    params: [
      name: {:string, required: true},
      code: :string,
      slug: :string,
      description: :string
    ]

  alias Amauta.{Authorization, Pathways}

  @impl true
  def authorize(scope, _input), do: Authorization.authorize(scope, "institution.pathways.create")

  @impl true
  def run(scope, input), do: Pathways.create(scope, input)
end

defmodule Amauta.Pathways.Actions.UpdatePathway do
  @moduledoc "Edita los datos de un trayecto (RF-TRA-001)."
  use Amauta.Action,
    name: "pathways.pathway.update",
    description: "Edita los datos de un trayecto.",
    params: [
      pathway_id: {Ecto.UUID, required: true},
      name: :string,
      code: :string,
      slug: :string,
      description: :string
    ]

  alias Amauta.Pathways.Actions.Helpers
  alias Amauta.Pathways.Pathway
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(scope, %{pathway_id: id}),
    do: Helpers.authorize_pathway(scope, id, "pathway.update")

  @impl true
  def run(scope, %{pathway_id: id} = input) do
    with {:ok, pathway} <- Helpers.fetch_editable_pathway(scope, id) do
      pathway
      |> Pathway.changeset(Map.delete(input, :pathway_id))
      |> Repo.update(Tenancy.opts(scope))
    end
  end
end

defmodule Amauta.Pathways.Actions.PublishPathway do
  @moduledoc "Publica un trayecto en borrador."
  use Amauta.Action,
    name: "pathways.pathway.publish",
    description: "Publica un trayecto.",
    params: [pathway_id: {Ecto.UUID, required: true}]

  alias Amauta.Pathways.Actions.Helpers

  @impl true
  def authorize(scope, %{pathway_id: id}),
    do: Helpers.authorize_pathway(scope, id, "pathway.update")

  @impl true
  def run(scope, %{pathway_id: id}), do: Helpers.transition(scope, id, ~w(draft), "published")
end

defmodule Amauta.Pathways.Actions.ArchivePathway do
  @moduledoc "Archiva un trayecto: queda de solo lectura (ERS 4.8, RF-INS-003)."
  use Amauta.Action,
    name: "pathways.pathway.archive",
    description: "Archiva un trayecto.",
    params: [pathway_id: {Ecto.UUID, required: true}]

  alias Amauta.Pathways.Actions.Helpers

  @impl true
  def authorize(scope, %{pathway_id: id}),
    do: Helpers.authorize_pathway(scope, id, "pathway.archive")

  @impl true
  def run(scope, %{pathway_id: id}),
    do: Helpers.transition(scope, id, ~w(draft published), "archived")
end

defmodule Amauta.Pathways.Actions.ReopenPathway do
  @moduledoc "Reabre un trayecto archivado: vuelve a publicado."
  use Amauta.Action,
    name: "pathways.pathway.reopen",
    description: "Reabre un trayecto archivado.",
    params: [pathway_id: {Ecto.UUID, required: true}]

  alias Amauta.Pathways.Actions.Helpers

  @impl true
  def authorize(scope, %{pathway_id: id}),
    do: Helpers.authorize_pathway(scope, id, "pathway.archive")

  @impl true
  def run(scope, %{pathway_id: id}), do: Helpers.transition(scope, id, ~w(archived), "published")
end

defmodule Amauta.Pathways.Actions.AddStage do
  @moduledoc "Agrega una etapa al final de un trayecto (RF-TRA-002)."
  use Amauta.Action,
    name: "pathways.stage.create",
    description: "Agrega una etapa a un trayecto.",
    params: [
      pathway_id: {Ecto.UUID, required: true},
      name: {:string, required: true}
    ]

  alias Amauta.Pathways
  alias Amauta.Pathways.Actions.Helpers

  @impl true
  def authorize(scope, %{pathway_id: id}),
    do: Helpers.authorize_pathway(scope, id, "pathway.structure.update")

  @impl true
  def run(scope, %{pathway_id: id} = input) do
    with {:ok, pathway} <- Helpers.fetch_editable_pathway(scope, id) do
      Pathways.add_stage(scope, pathway, Map.delete(input, :pathway_id))
    end
  end
end

defmodule Amauta.Pathways.Actions.RenameStage do
  @moduledoc "Cambia el nombre de una etapa."
  use Amauta.Action,
    name: "pathways.stage.update",
    description: "Cambia el nombre de una etapa.",
    params: [
      stage_id: {Ecto.UUID, required: true},
      name: {:string, required: true}
    ]

  alias Amauta.Pathways.Actions.Helpers
  alias Amauta.Pathways.Stage
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(scope, %{stage_id: id}),
    do: Helpers.authorize_stage(scope, id, "pathway.structure.update")

  @impl true
  def run(scope, %{stage_id: id, name: name}) do
    with {:ok, stage} <- Helpers.fetch_stage(scope, id) do
      stage |> Stage.changeset(%{name: name}) |> Repo.update(Tenancy.opts(scope))
    end
  end
end

defmodule Amauta.Pathways.Actions.MoveStage do
  @moduledoc "Mueve una etapa un lugar hacia arriba o hacia abajo."
  use Amauta.Action,
    name: "pathways.stage.move",
    description: "Reordena las etapas de un trayecto.",
    params: [
      stage_id: {Ecto.UUID, required: true},
      direction: {:string, required: true}
    ]

  import Ecto.Changeset

  alias Amauta.Pathways
  alias Amauta.Pathways.Actions.Helpers

  @impl true
  def validate(changeset), do: validate_inclusion(changeset, :direction, ~w(up down))

  @impl true
  def authorize(scope, %{stage_id: id}),
    do: Helpers.authorize_stage(scope, id, "pathway.structure.update")

  @impl true
  def run(scope, %{stage_id: id, direction: direction}) do
    with {:ok, stage} <- Helpers.fetch_stage(scope, id) do
      Pathways.move_stage(scope, stage, String.to_existing_atom(direction))
    end
  end
end

defmodule Amauta.Pathways.Actions.DeleteStage do
  @moduledoc "Borra una etapa de un trayecto."
  use Amauta.Action,
    name: "pathways.stage.delete",
    description: "Borra una etapa de un trayecto.",
    params: [stage_id: {Ecto.UUID, required: true}]

  alias Amauta.Pathways
  alias Amauta.Pathways.Actions.Helpers

  @impl true
  def authorize(scope, %{stage_id: id}),
    do: Helpers.authorize_stage(scope, id, "pathway.structure.update")

  @impl true
  def run(scope, %{stage_id: id}) do
    with {:ok, stage} <- Helpers.fetch_stage(scope, id) do
      Pathways.delete_stage(scope, stage)
    end
  end
end
