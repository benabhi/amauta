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
  alias Amauta.Feed.{Attachment, Mute, Post, Reply}
  alias Amauta.Files
  alias Amauta.Files.StoredFile
  alias Amauta.{Authorization, Repo, Scope, Tenancy}

  @page 30
  @reply_window 3
  @child_window 2

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

  @doc """
  Puede adjuntar archivos en el tablón (RF-TAB-005): quien puede publicar
  o responder; los estudiantes, si el curso lo permite.
  """
  def can_attach?(%Scope{} = scope, %Course{} = course) do
    (can_post?(scope, course) or can_reply?(scope, course)) and
      (course.settings.student_attachments != false or
         Enrollments.can_in_course?(scope, "course.feed.post", course))
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
  aparte (`list_pinned/4`).

  Trae de a `page_size/0`. Opciones: `:before`, la última publicación ya
  mostrada (para traer las anteriores), y `:windows`, cuántas respuestas
  mostrar (ver `with_replies/3`).
  """
  def list_posts(%Scope{} = scope, %Course{} = course, filters \\ %{}, opts \\ []) do
    Post
    |> where([p], p.course_id == ^course.id and p.status == "published")
    |> where([p], not pinned(p, ^DateTime.utc_now()))
    |> visible_to(scope, course)
    |> filter_section(filters["section"])
    |> before(opts[:before])
    |> order_by([p], desc: p.published_at, desc: p.id)
    |> limit(@page)
    |> preload([:author, :section, attachments: :file])
    |> Repo.all(Tenancy.opts(scope))
    |> with_replies(scope, opts[:windows] || %{})
  end

  @doc """
  Publicaciones fijadas y vigentes que la persona ve (RF-TAB-006), en el
  orden que eligió el equipo docente. Acepta el mismo filtro de comisión
  que `list_posts/4`; también acepta `:windows`.
  """
  def list_pinned(%Scope{} = scope, %Course{} = course, filters \\ %{}, opts \\ []) do
    Post
    |> where([p], p.course_id == ^course.id and p.status == "published")
    |> where([p], pinned(p, ^DateTime.utc_now()))
    |> visible_to(scope, course)
    |> filter_section(filters["section"])
    |> order_by([p], asc: p.pin_position, asc: p.pinned_at)
    |> preload([:author, :section, attachments: :file])
    |> Repo.all(Tenancy.opts(scope))
    |> with_replies(scope, opts[:windows] || %{})
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

  @doc "Cuántas publicaciones trae `list_posts/4` por vez."
  def page_size, do: @page

  @doc "Cuántas respuestas de primer nivel se muestran por defecto."
  def reply_window, do: @reply_window

  @doc "Cuántas respuestas anidadas se muestran por defecto."
  def child_window, do: @child_window

  defp before(query, nil), do: query

  defp before(query, %Post{published_at: at, id: id}),
    do: where(query, [p], p.published_at < ^at or (p.published_at == ^at and p.id < ^id))

  @doc """
  Carga las respuestas que se muestran de cada publicación (RF-TAB-004),
  sin traer hilos enteros: con 3 o con 3000 respuestas, el costo es el
  mismo. Cada publicación lleva sus conteos (`reply_count`,
  `top_reply_count`) y en `replies` las últimas de primer nivel, cada una
  con su `child_count` y sus últimas anidadas en `children`, en orden
  cronológico.

  `windows` dice cuántas mostrar: por ID de publicación (de primer nivel,
  por defecto #{@reply_window}) y por ID de respuesta (anidadas, por
  defecto #{@child_window}). Es lo que agranda «Ver anteriores».
  """
  def with_replies(posts, tenant, windows \\ %{})
  def with_replies([], _tenant, _windows), do: []

  def with_replies(posts, tenant, windows) do
    opts = Tenancy.opts(tenant)
    ids = Enum.map(posts, & &1.id)

    counts =
      from(r in Reply,
        where: r.post_id in ^ids,
        group_by: r.post_id,
        select: {r.post_id, {count(r.id), filter(count(r.id), is_nil(r.parent_id))}}
      )
      |> Repo.all(opts)
      |> Map.new()

    tops = latest(ids, :post_id, windows, @reply_window, opts)
    top_ids = Enum.map(tops, & &1.id)

    child_counts =
      from(r in Reply,
        where: r.parent_id in ^top_ids,
        group_by: r.parent_id,
        select: {r.parent_id, count(r.id)}
      )
      |> Repo.all(opts)
      |> Map.new()

    children =
      top_ids |> latest(:parent_id, windows, @child_window, opts) |> Enum.group_by(& &1.parent_id)

    tops =
      tops
      |> Enum.map(fn reply ->
        %{
          reply
          | child_count: Map.get(child_counts, reply.id, 0),
            children: Map.get(children, reply.id, [])
        }
      end)
      |> Enum.group_by(& &1.post_id)

    Enum.map(posts, fn post ->
      {total, top} = Map.get(counts, post.id, {0, 0})
      %{post | reply_count: total, top_reply_count: top, replies: Map.get(tops, post.id, [])}
    end)
  end

  # Las últimas `n` respuestas de cada padre (publicación o respuesta), con
  # su autor y en orden cronológico. Una consulta por cada tamaño de ventana
  # distinto: casi siempre, una sola.
  defp latest([], _parent, _windows, _default, _opts), do: []

  defp latest(parent_ids, parent, windows, default, opts) do
    parent_ids
    |> Enum.group_by(&Map.get(windows, &1, default))
    |> Enum.flat_map(fn {n, ids} ->
      ranked =
        from(r in Reply,
          where: field(r, ^parent) in ^ids,
          where: ^if(parent == :post_id, do: dynamic([r], is_nil(r.parent_id)), else: true),
          select: %{
            id: r.id,
            rank:
              over(row_number(),
                partition_by: field(r, ^parent),
                order_by: [desc: r.inserted_at, desc: r.id]
              )
          }
        )

      from(r in Reply,
        join: x in subquery(ranked),
        on: x.id == r.id,
        where: x.rank <= ^n,
        order_by: [asc: r.inserted_at, asc: r.id],
        preload: [:author, attachments: :file]
      )
      |> Repo.all(opts)
    end)
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

  @doc """
  Publicación visible por ID, con autor, comisión y las respuestas que se
  muestran (opción `:windows`, ver `with_replies/3`), o `nil`.
  """
  def get_visible(%Scope{} = scope, %Course{} = course, id, opts \\ []) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Post{} = post <-
           Post
           |> where([p], p.id == ^id and p.course_id == ^course.id and p.status == "published")
           |> visible_to(scope, course)
           |> preload([:author, :section, attachments: :file])
           |> Repo.one(Tenancy.opts(scope)) do
      [post] = with_replies([post], scope, opts[:windows] || %{})
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

  ## Adjuntos (RF-TAB-005)

  @max_attachments 10

  @doc "Cuántos archivos se pueden adjuntar a una publicación o respuesta."
  def max_attachments, do: @max_attachments

  @doc """
  Deja adjuntos a una publicación o respuesta exactamente los archivos de
  `file_ids`, en ese orden: vincula los nuevos, reordena los que ya estaban
  y descarta los que se quitaron. Los nuevos tienen que ser archivos listos
  del tablón, subidos por la persona para ese curso y sin vincular. Con
  `nil` no cambia nada.
  """
  def sync_attachments(_scope, _owner, _course, nil), do: :ok

  def sync_attachments(%Scope{} = scope, owner, %Course{} = course, file_ids) do
    opts = Tenancy.opts(scope)
    ids = Enum.uniq(file_ids)
    {key, owner_id} = owner_key(owner)

    current =
      from(a in Attachment, where: field(a, ^key) == ^owner_id, preload: :file)
      |> Repo.all(opts)

    current_ids = Enum.map(current, & &1.file_id)
    new_ids = ids -- current_ids

    valid =
      from(f in StoredFile,
        left_join: a in Attachment,
        on: a.file_id == f.id,
        where: f.id in ^new_ids and is_nil(a.id),
        where: f.purpose == "feed_attachment" and f.status == "ready",
        where: f.uploaded_by_id == ^scope.user.id and f.owner_id == ^course.id,
        select: f.id
      )
      |> Repo.all(opts)

    cond do
      length(ids) > @max_attachments ->
        {:error, :too_many_attachments}

      length(valid) != length(new_ids) ->
        {:error, :invalid_attachment}

      true ->
        for attachment <- current, attachment.file_id not in ids do
          Repo.delete!(attachment, opts)
          Files.discard(scope, attachment.file)
        end

        ids
        |> Enum.with_index()
        |> Enum.each(fn {file_id, position} ->
          %Attachment{file_id: file_id, position: position}
          |> Map.put(key, owner_id)
          |> Repo.insert!(
            Keyword.merge(opts,
              on_conflict: [set: [position: position]],
              conflict_target: :file_id
            )
          )
        end)

        :ok
    end
  end

  @doc "Archivos adjuntos a una publicación o respuesta, en orden."
  def attached_files(%Scope{} = scope, owner) do
    {key, owner_id} = owner_key(owner)

    from(a in Attachment,
      join: f in assoc(a, :file),
      where: field(a, ^key) == ^owner_id,
      order_by: a.position,
      select: f
    )
    |> Repo.all(Tenancy.opts(scope))
  end

  defp owner_key(%Post{id: id}), do: {:post_id, id}
  defp owner_key(%Reply{id: id}), do: {:reply_id, id}

  @doc """
  Descarta del almacenamiento los adjuntos de una publicación (y de sus
  respuestas) o de una respuesta (y de sus anidadas), antes de borrarla.
  """
  def discard_attachments(%Scope{} = scope, owner) do
    opts = Tenancy.opts(scope)

    query =
      case owner do
        %Post{id: id} ->
          from(a in Attachment,
            left_join: r in Reply,
            on: r.id == a.reply_id,
            where: a.post_id == ^id or r.post_id == ^id
          )

        %Reply{id: id} ->
          from(a in Attachment,
            left_join: r in Reply,
            on: r.id == a.reply_id,
            where: a.reply_id == ^id or r.parent_id == ^id
          )
      end

    query
    |> preload(:file)
    |> Repo.all(opts)
    |> Enum.each(&Files.discard(scope, &1.file))
  end

  @doc """
  Puede ver un adjunto del tablón: quien lo subió (antes de publicar) o
  quien ve la publicación a la que pertenece.
  """
  def can_view_attachment?(%Scope{user: %{id: user_id}}, %StoredFile{uploaded_by_id: user_id}),
    do: true

  def can_view_attachment?(%Scope{} = scope, %StoredFile{id: file_id}) do
    post_id =
      from(a in Attachment,
        left_join: r in Reply,
        on: r.id == a.reply_id,
        where: a.file_id == ^file_id,
        select: coalesce(a.post_id, r.post_id)
      )
      |> Repo.one(Tenancy.opts(scope))

    # La URL del archivo anda por fuera del tablón: hay que poder ver el
    # curso, además de la publicación.
    with %Post{status: "published", course: course} <- post_id && get(scope, post_id),
         true <- Enrollments.can_in_course?(scope, "course.view", course) do
      Post
      |> where([p], p.id == ^post_id)
      |> visible_to(scope, course)
      |> Repo.exists?(Tenancy.opts(scope))
    else
      _ -> false
    end
  end

  ## Tiempo real

  @doc "Avisa un cambio a quienes miran el tablón: `{:feed, :published | :updated | :deleted, post}`."
  def broadcast(%Course{} = course, event, post) do
    Phoenix.PubSub.broadcast(Amauta.PubSub, topic(course), {:feed, event, post})
  end
end
