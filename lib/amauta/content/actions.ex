defmodule Amauta.Content.Actions.Helpers do
  @moduledoc false
  alias Amauta.Content
  alias Amauta.Content.{Item, Unit}
  alias Amauta.{Courses, Repo, Tenancy}

  def fetch_course(scope, id) do
    case Courses.get(scope, id) do
      nil -> {:error, :not_found}
      course -> {:ok, course}
    end
  end

  @doc "Puede gestionar el contenido del curso (que no esté archivado)."
  def authorize_course(scope, course_id) do
    with {:ok, course} <- fetch_course(scope, course_id) do
      if Content.can_manage?(scope, course), do: :ok, else: {:error, :forbidden}
    end
  end

  def fetch_unit(scope, id) do
    case Repo.get(Unit, id, Tenancy.opts(scope)) do
      nil -> {:error, :not_found}
      unit -> {:ok, Repo.preload(unit, :course, Tenancy.opts(scope))}
    end
  end

  def fetch_item(scope, id) do
    case Repo.get(Item, id, Tenancy.opts(scope)) do
      nil -> {:error, :not_found}
      item -> {:ok, Repo.preload(item, [:course, :unit], Tenancy.opts(scope))}
    end
  end

  def authorize_unit(scope, id) do
    with {:ok, unit} <- fetch_unit(scope, id), do: authorize_course(scope, unit.course_id)
  end

  def authorize_item(scope, id) do
    with {:ok, item} <- fetch_item(scope, id), do: authorize_course(scope, item.course_id)
  end

  @doc "Inserta `id` en la posición `index` (desde 0) de la lista, acotada."
  def place(ids, id, index) do
    ids = List.delete(ids, id)
    List.insert_at(ids, min(max(index, 0), length(ids)), id)
  end

  # El cuerpo puede ser largo: no va a la auditoría.
  def audit_input(input), do: Map.drop(input, [:body])
end

defmodule Amauta.Content.Actions.CreateUnit do
  @moduledoc "Crea una unidad al final del contenido del curso (RF-CON-001)."
  use Amauta.Action,
    name: "content.unit.create",
    description: "Crea una unidad en el contenido del curso.",
    params: [
      course_id: {Ecto.UUID, required: true},
      title: {:string, required: true},
      description: :string,
      starts_on: :date,
      ends_on: :date,
      visibility: :string,
      publish_at: :utc_datetime_usec
    ]

  alias Amauta.Content
  alias Amauta.Content.Actions.Helpers
  alias Amauta.Content.Unit
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(scope, %{course_id: id}), do: Helpers.authorize_course(scope, id)

  @impl true
  def run(scope, %{course_id: course_id} = input) do
    position = Content.next_position(scope, Unit, :course_id, course_id)

    %Unit{course_id: course_id, position: position}
    |> Unit.changeset(Map.delete(input, :course_id))
    |> Repo.insert(Tenancy.opts(scope))
  end

  @impl true
  def effects(scope, _input, unit), do: Content.publication_jobs(scope, unit)
end

defmodule Amauta.Content.Actions.UpdateUnit do
  @moduledoc "Edita una unidad: título, descripción, fechas y visibilidad (RF-CON-001)."
  use Amauta.Action,
    name: "content.unit.update",
    description: "Edita una unidad del contenido del curso.",
    params: [
      unit_id: {Ecto.UUID, required: true},
      title: :string,
      description: :string,
      starts_on: :date,
      ends_on: :date,
      visibility: :string,
      publish_at: :utc_datetime_usec
    ]

  alias Amauta.Content
  alias Amauta.Content.Actions.Helpers
  alias Amauta.Content.Unit
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(scope, %{unit_id: id}), do: Helpers.authorize_unit(scope, id)

  @impl true
  def run(scope, %{unit_id: id} = input) do
    with {:ok, unit} <- Helpers.fetch_unit(scope, id) do
      unit
      |> Unit.changeset(Map.delete(input, :unit_id))
      |> Repo.update(Tenancy.opts(scope))
    end
  end

  @impl true
  def effects(scope, _input, unit), do: Content.publication_jobs(scope, unit)

  # Mostrar u ocultar la unidad cambia lo que ve el estudiantado de todos sus
  # elementos: sus tarjetas en el tablón se ponen al día.
  @impl true
  def after_commit(scope, _input, unit) do
    for id <- Content.item_ids(scope, unit),
        do: scope |> Content.sync_announcement(id) |> Content.broadcast_announcement()

    :ok
  end
end

defmodule Amauta.Content.Actions.DeleteUnit do
  @moduledoc """
  Borra una unidad con todos sus elementos. Los archivos de sus materiales
  se descartan del almacenamiento.
  """
  use Amauta.Action,
    name: "content.unit.delete",
    description: "Borra una unidad del contenido del curso, con sus elementos.",
    params: [unit_id: {Ecto.UUID, required: true}]

  import Ecto.Query

  alias Amauta.Content
  alias Amauta.Content.Actions.Helpers
  alias Amauta.Content.Item
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(scope, %{unit_id: id}), do: Helpers.authorize_unit(scope, id)

  @impl true
  def run(scope, %{unit_id: id}) do
    with {:ok, unit} <- Helpers.fetch_unit(scope, id) do
      item_ids =
        from(i in Item, where: i.unit_id == ^unit.id, select: i.id)
        |> Repo.all(Tenancy.opts(scope))

      cards = Content.cards(scope, item_ids)
      Content.discard_files(scope, item_ids)

      with {:ok, unit} <- Repo.delete(unit, Tenancy.opts(scope)),
           do: {:ok, %{unit: unit, cards: cards}}
    end
  end

  @impl true
  def audit(_scope, input, %{unit: unit}), do: {unit, input}

  # Sus tarjetas se borraron con los elementos: fuera del tablón abierto.
  @impl true
  def after_commit(_scope, _input, %{cards: cards}) do
    for card <- cards, do: Amauta.Feed.broadcast(card.course, :deleted, card)
    :ok
  end
end

defmodule Amauta.Content.Actions.MoveUnit do
  @moduledoc """
  Cambia de lugar una unidad dentro del curso (RF-CON-001): arrastrándola o
  con el teclado. `index` es la posición nueva, desde 0.
  """
  use Amauta.Action,
    name: "content.unit.move",
    description: "Cambia el orden de una unidad en el contenido del curso.",
    params: [unit_id: {Ecto.UUID, required: true}, index: {:integer, required: true}]

  import Ecto.Query

  alias Amauta.Content
  alias Amauta.Content.Actions.Helpers
  alias Amauta.Content.Unit
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(scope, %{unit_id: id}), do: Helpers.authorize_unit(scope, id)

  @impl true
  def run(scope, %{unit_id: id, index: index}) do
    with {:ok, unit} <- Helpers.fetch_unit(scope, id) do
      ids =
        from(u in Unit,
          where: u.course_id == ^unit.course_id,
          order_by: [asc: u.position, asc: u.inserted_at],
          select: u.id
        )
        |> Repo.all(Tenancy.opts(scope))
        |> Helpers.place(unit.id, index)

      Content.write_order(scope, Unit, ids)
      {:ok, unit}
    end
  end

  @impl true
  def audit(_scope, input, unit), do: {unit, input}
end

defmodule Amauta.Content.Actions.CreateItem do
  @moduledoc """
  Crea un elemento al final de una unidad (RF-CON-002): una página o un
  material, con sus archivos.
  """
  use Amauta.Action,
    name: "content.item.create",
    description: "Crea una página o un material en una unidad.",
    params: [
      unit_id: {Ecto.UUID, required: true},
      kind: {:string, required: true},
      title: {:string, required: true},
      body: :string,
      url: :string,
      visibility: :string,
      publish_at: :utc_datetime_usec,
      announce: :boolean,
      file_ids: {{:array, Ecto.UUID}, []}
    ]

  alias Amauta.Content
  alias Amauta.Content.Actions.Helpers
  alias Amauta.Content.Item
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(scope, %{unit_id: id}), do: Helpers.authorize_unit(scope, id)

  @impl true
  def run(scope, %{unit_id: unit_id} = input) do
    with {:ok, unit} <- Helpers.fetch_unit(scope, unit_id),
         {:ok, item} <-
           %Item{
             course_id: unit.course_id,
             unit_id: unit.id,
             created_by_id: scope.user.id,
             position: Content.next_position(scope, Item, :unit_id, unit.id)
           }
           |> Item.create_changeset(Map.drop(input, [:unit_id, :file_ids]))
           |> Repo.insert(Tenancy.opts(scope)),
         :ok <- Content.sync_files(scope, item, unit.course, input[:file_ids]) do
      {:ok, item}
    end
  end

  @impl true
  def audit(_scope, input, item), do: {item, Helpers.audit_input(input)}

  @impl true
  def effects(scope, _input, item), do: Content.publication_jobs(scope, item)

  @impl true
  def after_commit(scope, _input, item) do
    scope |> Content.sync_announcement(item) |> Content.broadcast_announcement()
  end
end

defmodule Amauta.Content.Actions.UpdateItem do
  @moduledoc "Edita un elemento: título, contenido, enlace, archivos y visibilidad."
  use Amauta.Action,
    name: "content.item.update",
    description: "Edita una página o un material.",
    params: [
      item_id: {Ecto.UUID, required: true},
      title: :string,
      body: :string,
      url: :string,
      visibility: :string,
      publish_at: :utc_datetime_usec,
      announce: :boolean,
      file_ids: {{:array, Ecto.UUID}, []}
    ]

  alias Amauta.Content
  alias Amauta.Content.Actions.Helpers
  alias Amauta.Content.Item
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(scope, %{item_id: id}), do: Helpers.authorize_item(scope, id)

  @impl true
  def run(scope, %{item_id: id} = input) do
    with {:ok, item} <- Helpers.fetch_item(scope, id),
         {:ok, updated} <-
           item
           |> Item.changeset(Map.drop(input, [:item_id, :file_ids]))
           |> Repo.update(Tenancy.opts(scope)),
         :ok <- Content.sync_files(scope, updated, item.course, input[:file_ids]) do
      {:ok, updated}
    end
  end

  @impl true
  def audit(_scope, input, item), do: {item, Helpers.audit_input(input)}

  @impl true
  def effects(scope, _input, item), do: Content.publication_jobs(scope, item)

  @impl true
  def after_commit(scope, _input, item) do
    scope |> Content.sync_announcement(item) |> Content.broadcast_announcement()
  end
end

defmodule Amauta.Content.Actions.DeleteItem do
  @moduledoc "Borra un elemento; los archivos de un material se descartan del almacenamiento."
  use Amauta.Action,
    name: "content.item.delete",
    description: "Borra una página o un material.",
    params: [item_id: {Ecto.UUID, required: true}]

  alias Amauta.Content
  alias Amauta.Content.Actions.Helpers
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(scope, %{item_id: id}), do: Helpers.authorize_item(scope, id)

  @impl true
  def run(scope, %{item_id: id}) do
    with {:ok, item} <- Helpers.fetch_item(scope, id) do
      cards = Content.cards(scope, [item.id])
      Content.discard_files(scope, [item.id])

      with {:ok, item} <- Repo.delete(item, Tenancy.opts(scope)),
           do: {:ok, %{item: item, cards: cards}}
    end
  end

  @impl true
  def audit(_scope, input, %{item: item}), do: {item, input}

  @impl true
  def after_commit(_scope, _input, %{cards: cards}) do
    for card <- cards, do: Amauta.Feed.broadcast(card.course, :deleted, card)
    :ok
  end
end

defmodule Amauta.Content.Actions.MoveItem do
  @moduledoc """
  Mueve un elemento dentro de su unidad o a otra del mismo curso
  (RF-CON-004): arrastrándolo o con el teclado. `index` es la posición nueva
  en la unidad de destino, desde 0.
  """
  use Amauta.Action,
    name: "content.item.move",
    description: "Mueve una página o un material dentro de su unidad o a otra.",
    params: [
      item_id: {Ecto.UUID, required: true},
      unit_id: {Ecto.UUID, required: true},
      index: {:integer, required: true}
    ]

  import Ecto.Query

  alias Amauta.Content
  alias Amauta.Content.Actions.Helpers
  alias Amauta.Content.Item
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(scope, %{item_id: id}), do: Helpers.authorize_item(scope, id)

  @impl true
  def run(scope, %{item_id: id, unit_id: unit_id, index: index}) do
    opts = Tenancy.opts(scope)

    with {:ok, item} <- Helpers.fetch_item(scope, id),
         {:ok, unit} <- Helpers.fetch_unit(scope, unit_id),
         true <- unit.course_id == item.course_id || {:error, :not_found} do
      if unit.id != item.unit_id do
        from(i in Item, where: i.id == ^item.id)
        |> Repo.update_all([set: [unit_id: unit.id]], opts)
      end

      ids =
        from(i in Item,
          where: i.unit_id == ^unit.id,
          order_by: [asc: i.position, asc: i.inserted_at],
          select: i.id
        )
        |> Repo.all(opts)
        |> Helpers.place(item.id, index)

      Content.write_order(scope, Item, ids)
      {:ok, %{item | unit_id: unit.id}}
    end
  end

  @impl true
  def audit(_scope, input, item), do: {item, input}

  # En otra unidad puede cambiar lo que ve el estudiantado.
  @impl true
  def after_commit(scope, _input, item) do
    scope |> Content.sync_announcement(item) |> Content.broadcast_announcement()
  end
end

defmodule Amauta.Content.Actions.SetItemDone do
  @moduledoc """
  Marca o desmarca un elemento como hecho (RF-CON-006, «marcar como
  hecho»). Lo hace quien cursa, sobre lo que puede ver. No se audita: es el
  registro personal del avance, no un cambio en el curso.
  """
  use Amauta.Action,
    name: "content.item.set_done",
    description: "Marca o desmarca un elemento del contenido como hecho.",
    params: [item_id: {Ecto.UUID, required: true}, done: {:boolean, required: true}]

  alias Amauta.Content
  alias Amauta.Content.Actions.Helpers

  @impl true
  def authorize(scope, %{item_id: id}) do
    with {:ok, item} <- Helpers.fetch_item(scope, id) do
      if Content.tracks_progress?(scope, item.course) and Content.get_item(scope, item.course, id),
        do: :ok,
        else: {:error, :forbidden}
    end
  end

  @impl true
  def run(scope, %{item_id: id, done: done}) do
    with {:ok, item} <- Helpers.fetch_item(scope, id),
         {:ok, _} <- Content.set_done(scope, item, done) do
      {:ok, %{item_id: item.id, done: done}}
    end
  end

  @impl true
  def audit(_scope, _input, _result), do: :skip
end
