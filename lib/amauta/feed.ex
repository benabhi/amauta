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
  alias Amauta.Feed.{Mute, Post, Reply}
  alias Amauta.{Authorization, Repo, Scope, Tenancy}

  @page 30

  # Fijada y vigente (RF-TAB-006).
  defmacrop pinned(p, now) do
    quote do
      not is_nil(unquote(p).pinned_at) and
        (is_nil(unquote(p).pin_expires_at) or unquote(p).pin_expires_at > unquote(now))
    end
  end

  ## Permisos

  @doc "Ve todas las publicaciones del curso (no está limitado a una comisión)."
  def sees_all?(%Scope{} = scope, %Course{} = course),
    do: Authorization.can?(scope, "course.feed.moderate", course)

  @doc "Puede publicar en el tablón del curso (y no está silenciada)."
  def can_post?(%Scope{} = scope, %Course{status: status} = course) when status != "archived" do
    not muted?(scope, course) and
      (Enrollments.can_in_course?(scope, "course.feed.post", course) or
         (course.settings.feed_posting == "everyone" and
            Enrollments.can_in_course?(scope, "course.feed.reply", course)))
  end

  def can_post?(_scope, _course), do: false

  @doc """
  Puede responder en el curso (RF-TAB-004): el curso tiene los comentarios
  activados, la persona no está silenciada y tiene el permiso de responder.
  Que la publicación los acepte se verifica aparte (`replies_open?/1`).
  """
  def can_reply?(%Scope{} = scope, %Course{status: status} = course) when status != "archived" do
    course.settings.comments_enabled and not muted?(scope, course) and
      Enrollments.can_in_course?(scope, "course.feed.reply", course)
  end

  def can_reply?(_scope, _course), do: false

  @doc "La publicación acepta respuestas."
  def replies_open?(%Post{replies_enabled: enabled}), do: enabled

  @doc "La persona del scope está silenciada en el tablón del curso."
  def muted?(%Scope{user: nil}, _course), do: false
  def muted?(%Scope{user: user} = scope, course), do: muted?(scope, course, user.id)

  def muted?(tenant, %Course{id: course_id}, user_id) do
    Repo.exists?(
      from(m in Mute, where: m.course_id == ^course_id and m.user_id == ^user_id),
      Tenancy.opts(tenant)
    )
  end

  @doc "IDs de las personas silenciadas en el tablón del curso."
  def muted_ids(tenant, %Course{id: course_id}) do
    from(m in Mute, where: m.course_id == ^course_id, select: m.user_id)
    |> Repo.all(Tenancy.opts(tenant))
    |> MapSet.new()
  end

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
  curso entero (el filtro del encabezado, RF-COM-003). Las fijadas van
  aparte (`list_pinned/3`).
  """
  def list_posts(%Scope{} = scope, %Course{} = course, filters \\ %{}) do
    Post
    |> where([p], p.course_id == ^course.id and p.status == "published")
    |> where([p], not pinned(p, ^DateTime.utc_now()))
    |> visible_to(scope, course)
    |> filter_section(filters["section"])
    |> order_by([p], desc: p.published_at, desc: p.id)
    |> limit(@page)
    |> preload(^post_preloads())
    |> Repo.all(Tenancy.opts(scope))
  end

  @doc """
  Publicaciones fijadas y vigentes que la persona ve (RF-TAB-006), en el
  orden que eligió el equipo docente. Acepta el mismo filtro de comisión
  que `list_posts/3`.
  """
  def list_pinned(%Scope{} = scope, %Course{} = course, filters \\ %{}) do
    Post
    |> where([p], p.course_id == ^course.id and p.status == "published")
    |> where([p], pinned(p, ^DateTime.utc_now()))
    |> visible_to(scope, course)
    |> filter_section(filters["section"])
    |> order_by([p], asc: p.pin_position, asc: p.pinned_at)
    |> preload(^post_preloads())
    |> Repo.all(Tenancy.opts(scope))
  end

  @doc "La publicación está fijada y no venció."
  def pinned?(%Post{pinned_at: nil}, _now), do: false
  def pinned?(%Post{pin_expires_at: nil}, _now), do: true
  def pinned?(%Post{pin_expires_at: expires}, now), do: DateTime.compare(expires, now) == :gt

  @doc "IDs de las fijadas vigentes del curso, en orden (sin filtrar por visibilidad)."
  def pinned_ids(tenant, %Course{id: course_id}) do
    from(p in Post,
      where: p.course_id == ^course_id and p.status == "published",
      where: pinned(p, ^DateTime.utc_now()),
      order_by: [asc: p.pin_position, asc: p.pinned_at],
      select: p.id
    )
    |> Repo.all(Tenancy.opts(tenant))
  end

  # Autor, comisión y respuestas en orden, con sus autores.
  defp post_preloads do
    replies = from(r in Reply, order_by: [r.inserted_at, r.id], preload: :author)
    [:author, :section, replies: replies]
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
           |> preload(^post_preloads())
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

  @doc "Respuesta por ID, con su publicación y el curso, o `nil`."
  def get_reply(tenant, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Reply |> Repo.get(id, Tenancy.opts(tenant)) |> Repo.preload(post: :course)
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
