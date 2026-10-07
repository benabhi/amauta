defmodule Amauta.Content do
  @moduledoc """
  Contenido de un curso (capacidad C7): unidades ordenadas y, dentro de
  cada una, elementos (RF-CON-001, 002, 004 y 005).

  Quién ve qué:

    * Quien tiene `course.content.view_hidden` (el equipo docente) ve todo.
    * El resto ve las unidades y elementos visibles, o programados cuya
      fecha ya pasó. Un elemento de una unidad que no ve, tampoco lo ve.

  Modificar pasa por las acciones de `Amauta.Content.Actions` y exige
  `course.content.manage` en un curso que no esté archivado.
  """
  import Ecto.Query
  import Ecto.Changeset, only: [validate_inclusion: 3, get_field: 2, add_error: 3]

  alias Amauta.Content.{Completion, Item, ItemFile, Unit}
  alias Amauta.Courses.Course
  alias Amauta.Enrollments
  alias Amauta.Files
  alias Amauta.Files.StoredFile
  alias Amauta.{Repo, Scope, Tenancy}

  @max_files 10

  ## Permisos

  @doc "Puede ver el contenido del curso."
  def can_view?(%Scope{} = scope, %Course{} = course),
    do: Enrollments.can_in_course?(scope, "course.view", course)

  @doc "Ve también lo oculto y lo programado (RF-CON-005)."
  def can_view_hidden?(%Scope{} = scope, %Course{} = course),
    do: Enrollments.can_in_course?(scope, "course.content.view_hidden", course)

  @doc "Puede crear, editar, ordenar y borrar unidades y elementos."
  def can_manage?(%Scope{} = scope, %Course{status: status} = course) when status != "archived",
    do: Enrollments.can_in_course?(scope, "course.content.manage", course)

  def can_manage?(_scope, _course), do: false

  ## Visibilidad

  @doc false
  # Común a unidades y elementos: programado exige fecha.
  def validate_visibility(changeset) do
    changeset = validate_inclusion(changeset, :visibility, Unit.visibilities())

    if get_field(changeset, :visibility) == "scheduled" and
         is_nil(get_field(changeset, :publish_at)),
       do: add_error(changeset, :publish_at, "can't be blank"),
       else: changeset
  end

  @doc "Si una unidad o un elemento se ve sin permisos especiales."
  def published?(%{visibility: "visible"}), do: true

  def published?(%{visibility: "scheduled", publish_at: %DateTime{} = at}),
    do: not DateTime.after?(at, DateTime.utc_now())

  def published?(_unit_or_item), do: false

  defp published(query) do
    now = DateTime.utc_now()

    where(
      query,
      [x],
      x.visibility == "visible" or (x.visibility == "scheduled" and x.publish_at <= ^now)
    )
  end

  ## Consultas

  @doc """
  Unidades del curso con sus elementos, en orden, según lo que ve la
  persona.
  """
  def list_units(%Scope{} = scope, %Course{} = course) do
    hidden = can_view_hidden?(scope, course)
    items = from(i in Item, order_by: [asc: i.position, asc: i.inserted_at])
    items = if hidden, do: items, else: published(items)

    from(u in Unit,
      where: u.course_id == ^course.id,
      order_by: [asc: u.position, asc: u.inserted_at],
      preload: [items: ^items]
    )
    |> then(&if(hidden, do: &1, else: published(&1)))
    |> Repo.all(Tenancy.opts(scope))
  end

  @doc "Una unidad del curso, sin mirar la visibilidad (para quien gestiona)."
  def get_unit(%Scope{} = scope, %Course{} = course, id) do
    Repo.get_by(Unit, [id: id, course_id: course.id], Tenancy.opts(scope))
  end

  @doc """
  Un elemento del curso, con su unidad y sus archivos, si la persona lo
  puede ver.
  """
  def get_item(%Scope{} = scope, %Course{} = course, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Item{} = item <-
           Repo.get_by(Item, [id: id, course_id: course.id], Tenancy.opts(scope)),
         item = Repo.preload(item, [:unit, files: :file], Tenancy.opts(scope)),
         true <- can_view_hidden?(scope, course) or (published?(item.unit) and published?(item)) do
      item
    else
      _ -> nil
    end
  end

  @doc "Posición para agregar al final de una lista (unidades del curso o elementos de una unidad)."
  def next_position(%Scope{} = scope, queryable, field, id) do
    from(x in queryable, where: field(x, ^field) == ^id, select: max(x.position))
    |> Repo.one(Tenancy.opts(scope))
    |> Kernel.||(0)
    |> Kernel.+(1)
  end

  @doc "Escribe el orden de una lista de IDs (1, 2, 3…)."
  def write_order(%Scope{} = scope, queryable, ids) do
    opts = Tenancy.opts(scope)

    ids
    |> Enum.with_index(1)
    |> Enum.each(fn {id, position} ->
      from(x in queryable, where: x.id == ^id)
      |> Repo.update_all([set: [position: position]], opts)
    end)
  end

  ## Archivos de los materiales

  @doc "Cuántos archivos puede tener un material."
  def max_files, do: @max_files

  @doc "Archivos de un material, en orden."
  def files(%Scope{} = scope, %Item{id: id}) do
    from(f in ItemFile,
      join: s in assoc(f, :file),
      where: f.item_id == ^id,
      order_by: f.position,
      select: s
    )
    |> Repo.all(Tenancy.opts(scope))
  end

  @doc """
  Deja en el material exactamente esos archivos, en ese orden. Los nuevos
  tienen que ser del propósito `content_material`, de este curso, estar
  listos, haberlos subido esta persona y no estar en otro elemento. Los que
  se quitan se descartan del almacenamiento.
  """
  def sync_files(_scope, _item, _course, nil), do: :ok

  def sync_files(%Scope{} = scope, %Item{} = item, %Course{} = course, file_ids) do
    opts = Tenancy.opts(scope)
    ids = Enum.uniq(file_ids)

    current = from(f in ItemFile, where: f.item_id == ^item.id, preload: :file) |> Repo.all(opts)
    current_ids = Enum.map(current, & &1.file_id)
    new_ids = ids -- current_ids

    valid =
      from(f in StoredFile,
        left_join: l in ItemFile,
        on: l.file_id == f.id,
        where: f.id in ^new_ids and is_nil(l.id),
        where: f.purpose == "content_material" and f.status == "ready",
        where: f.uploaded_by_id == ^scope.user.id and f.owner_id == ^course.id,
        select: f.id
      )
      |> Repo.all(opts)

    cond do
      length(ids) > @max_files ->
        {:error, :too_many_files}

      length(valid) != length(new_ids) ->
        {:error, :invalid_file}

      true ->
        for link <- current, link.file_id not in ids do
          Repo.delete!(link, opts)
          Files.discard(scope, link.file)
        end

        ids
        |> Enum.with_index()
        |> Enum.each(fn {file_id, position} ->
          case Enum.find(current, &(&1.file_id == file_id)) do
            nil ->
              Repo.insert!(
                %ItemFile{item_id: item.id, file_id: file_id, position: position},
                opts
              )

            link ->
              link |> Ecto.Changeset.change(position: position) |> Repo.update!(opts)
          end
        end)

        :ok
    end
  end

  @doc "Descarta del almacenamiento los archivos de los elementos indicados (antes de borrarlos)."
  def discard_files(%Scope{} = scope, item_ids) do
    from(f in ItemFile, join: s in assoc(f, :file), where: f.item_id in ^item_ids, select: s)
    |> Repo.all(Tenancy.opts(scope))
    |> Enum.each(&Files.discard(scope, &1))
  end

  @doc """
  Puede ver un archivo de material: quien lo subió, o quien ve el elemento
  donde está.
  """
  def can_view_file?(%Scope{user: %{id: user_id}}, %StoredFile{uploaded_by_id: user_id}), do: true

  def can_view_file?(%Scope{} = scope, %StoredFile{id: file_id}) do
    item =
      from(f in ItemFile,
        join: i in assoc(f, :item),
        join: c in assoc(i, :course),
        where: f.file_id == ^file_id,
        select: %{item_id: i.id, course: c}
      )
      |> Repo.one(Tenancy.opts(scope))

    with %{item_id: id, course: course} <- item,
         true <- can_view?(scope, course),
         %Item{} <- get_item(scope, course, id) do
      true
    else
      _ -> false
    end
  end

  ## Recorrido y finalización (RF-CON-006 y 007)

  @doc """
  Si la persona lleva su progreso en el curso: quien cursa (ve el
  contenido publicado, sin lo oculto). El equipo docente no.
  """
  def tracks_progress?(%Scope{user: %{}} = scope, %Course{} = course),
    do: can_view?(scope, course) and not can_view_hidden?(scope, course)

  def tracks_progress?(_scope, _course), do: false

  @doc "IDs de los elementos del curso que la persona marcó como hechos."
  def completed_ids(%Scope{user: %{id: user_id}} = scope, %Course{id: course_id}) do
    from(c in Completion,
      where: c.course_id == ^course_id and c.user_id == ^user_id,
      select: c.item_id
    )
    |> Repo.all(Tenancy.opts(scope))
    |> MapSet.new()
  end

  def completed_ids(_scope, _course), do: MapSet.new()

  @doc "Marca (o desmarca) un elemento como hecho para la persona."
  def set_done(%Scope{user: %{id: user_id}} = scope, %Item{} = item, true) do
    %Completion{
      item_id: item.id,
      user_id: user_id,
      course_id: item.course_id,
      completed_at: DateTime.utc_now()
    }
    |> Repo.insert(
      Tenancy.opts(scope) ++ [on_conflict: :nothing, conflict_target: [:item_id, :user_id]]
    )
  end

  def set_done(%Scope{user: %{id: user_id}} = scope, %Item{id: item_id}, false) do
    from(c in Completion, where: c.item_id == ^item_id and c.user_id == ^user_id)
    |> Repo.delete_all(Tenancy.opts(scope))

    {:ok, nil}
  end

  @doc "Los elementos de las unidades, en el orden del curso."
  def sequence(units), do: Enum.flat_map(units, & &1.items)

  @doc "El elemento anterior y el siguiente en el recorrido del curso."
  def neighbors(units, item_id) do
    items = sequence(units)
    index = Enum.find_index(items, &(&1.id == item_id))

    case index do
      nil -> {nil, nil}
      0 -> {nil, Enum.at(items, 1)}
      i -> {Enum.at(items, i - 1), Enum.at(items, i + 1)}
    end
  end

  @doc "Cuántos elementos de la unidad están hechos, y cuántos tiene."
  def unit_progress(%Unit{items: items}, done),
    do: {Enum.count(items, &MapSet.member?(done, &1.id)), length(items)}
end
