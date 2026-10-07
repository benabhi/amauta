defmodule Amauta.Feed do
  @moduledoc """
  Tablón del curso (RF-TAB-001 a 003, 007 y 008). Solo consultas y
  operaciones sin permisos: los cambios pasan por `Amauta.Feed.Actions`.

  Quién ve qué: el equipo docente del curso y la administración ven todo;
  los demás ven lo dirigido al curso entero y a su comisión.

  Quién publica (RF-TAB-007, ajuste «quién publica en el tablón» del
  curso): el equipo docente siempre; los estudiantes, si el curso permite
  que publiquen todos. La moderación previa llega en V1: hasta entonces,
  «todos, con moderación» se comporta como «solo el equipo docente».

  Cada cambio se avisa por PubSub en el tema del curso (`topic/1`), para el
  tiempo real (RF-TAB-008).
  """
  import Ecto.Query

  alias Amauta.Courses.Course
  alias Amauta.Enrollments
  alias Amauta.Feed.Post
  alias Amauta.{Authorization, Repo, Scope, Tenancy}

  @page 30

  ## Permisos

  @doc "Ve todas las publicaciones del curso (no está limitado a una comisión)."
  def sees_all?(%Scope{} = scope, %Course{} = course),
    do: Authorization.can?(scope, "course.feed.moderate", course)

  @doc "Puede publicar en el tablón del curso."
  def can_post?(%Scope{} = scope, %Course{status: status} = course) when status != "archived" do
    Enrollments.can_in_course?(scope, "course.feed.post", course) or
      (course.settings.feed_posting == "everyone" and
         Enrollments.can_in_course?(scope, "course.feed.reply", course))
  end

  def can_post?(_scope, _course), do: false

  @doc "Puede moderar (ocultar o eliminar lo de otras personas)."
  def can_moderate?(%Scope{} = scope, %Course{} = course),
    do: Enrollments.can_in_course?(scope, "course.feed.moderate", course)

  @doc """
  A qué puede dirigir una publicación: `:any` (el curso entero o cualquier
  comisión) o la lista de destinos permitidos, donde `nil` es el curso
  entero. El docente de comisión, solo a las suyas; quien publica sin ser
  docente, al curso entero o a su comisión.
  """
  def targetable_sections(%Scope{} = scope, %Course{} = course) do
    own = scope |> Enrollments.own_sections(course) |> Enum.map(& &1.id)

    cond do
      own != [] -> own
      Enrollments.can_in_course?(scope, "course.feed.post", course) -> :any
      true -> [nil | section_ids(scope, course)]
    end
  end

  ## Consultas

  @doc "Tema de PubSub del tablón de un curso."
  def topic(%Course{id: id}), do: "feed:#{id}"

  @doc """
  Publicaciones visibles del curso, de la más reciente a la más vieja, con
  autor y comisión. Con `"section"`, solo las de esa comisión y las del
  curso entero (el filtro del encabezado, RF-COM-003).
  """
  def list_posts(%Scope{} = scope, %Course{} = course, filters \\ %{}) do
    Post
    |> where([p], p.course_id == ^course.id and p.status == "published")
    |> visible_to(scope, course)
    |> filter_section(filters["section"])
    |> order_by([p], desc: p.published_at, desc: p.id)
    |> limit(@page)
    |> preload([:author, :section])
    |> Repo.all(Tenancy.opts(scope))
  end

  defp visible_to(query, scope, course) do
    if sees_all?(scope, course) do
      query
    else
      ids = section_ids(scope, course)
      where(query, [p], is_nil(p.section_id) or p.section_id in ^ids)
    end
  end

  # Comisiones de la persona en el curso: la de su matrícula (si la tiene)
  # y, si es docente de comisión, las suyas.
  defp section_ids(%Scope{user: nil}, _course), do: []

  defp section_ids(scope, course) do
    own = scope |> Enrollments.own_sections(course) |> Enum.map(& &1.id)

    case Enrollments.get_by_user(scope, course, scope.user.id) do
      %{status: "active", section_id: id} when not is_nil(id) -> Enum.uniq([id | own])
      _ -> own
    end
  end

  defp filter_section(query, value) when value in [nil, ""], do: query
  defp filter_section(query, "none"), do: where(query, [p], is_nil(p.section_id))

  defp filter_section(query, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> where(query, [p], is_nil(p.section_id) or p.section_id == ^id)
      :error -> query
    end
  end

  @doc "Publicación visible por ID, con autor y comisión, o `nil`."
  def get_visible(%Scope{} = scope, %Course{} = course, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Post{} = post <-
           Post
           |> where([p], p.id == ^id and p.course_id == ^course.id and p.status == "published")
           |> visible_to(scope, course)
           |> preload([:author, :section])
           |> Repo.one(Tenancy.opts(scope)) do
      post
    else
      _ -> nil
    end
  end

  @doc "Publicación por ID (cualquier estado), con su curso, o `nil`."
  def get(tenant, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Post |> Repo.get(id, Tenancy.opts(tenant)) |> Repo.preload(:course)
      :error -> nil
    end
  end

  @doc "Borrador de la persona en el curso, o `nil`."
  def get_draft(%Scope{user: %{id: user_id}} = scope, %Course{id: course_id}) do
    Repo.get_by(
      Post,
      [course_id: course_id, author_id: user_id, status: "draft"],
      Tenancy.opts(scope)
    )
  end

  def get_draft(_scope, _course), do: nil

  ## Tiempo real

  @doc "Avisa un cambio a quienes miran el tablón: `{:feed, :published | :updated | :deleted, post}`."
  def broadcast(%Course{} = course, event, post) do
    Phoenix.PubSub.broadcast(Amauta.PubSub, topic(course), {:feed, event, post})
  end
end
