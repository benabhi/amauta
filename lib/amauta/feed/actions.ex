defmodule Amauta.Feed.Actions.Helpers do
  @moduledoc false
  alias Amauta.{Courses, Feed}

  def fetch_course(scope, id) do
    case Courses.get(scope, id) do
      nil -> {:error, :not_found}
      %{status: "archived"} -> {:error, :archived}
      course -> {:ok, course}
    end
  end

  @doc "Puede publicar y, si eligió una comisión, puede dirigirse a ella."
  def authorize_post(scope, course_id, section_id) do
    with {:ok, course} <- fetch_course(scope, course_id),
         true <- Feed.can_post?(scope, course) || {:error, :forbidden} do
      case Feed.targetable_sections(scope, course) do
        :any -> :ok
        own -> if section_id in own, do: :ok, else: {:error, :forbidden}
      end
    end
  end

  # La comisión tiene que ser del curso.
  def check_section(_scope, _course, nil), do: :ok

  def check_section(scope, course, section_id) do
    case Amauta.Enrollments.get_section(scope, section_id) do
      %{course_id: id} when id == course.id -> :ok
      _ -> {:error, :not_found}
    end
  end
end

defmodule Amauta.Feed.Actions.SaveDraft do
  @moduledoc """
  Guarda el borrador de una publicación mientras se escribe (RF-TAB-003).
  Hay uno por persona y curso. No se audita: lo que cuenta es publicar.
  """
  use Amauta.Action,
    name: "feed.post.save_draft",
    description: "Guarda el borrador de una publicación del tablón.",
    params: [
      course_id: {Ecto.UUID, required: true},
      body: :string,
      section_id: Ecto.UUID,
      attachment_ids: {{:array, Ecto.UUID}, []}
    ]

  alias Amauta.Feed
  alias Amauta.Feed.Actions.Helpers
  alias Amauta.Feed.Post
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(scope, %{course_id: id} = input),
    do: Helpers.authorize_post(scope, id, input[:section_id])

  @impl true
  def run(scope, %{course_id: id} = input) do
    with {:ok, course} <- Helpers.fetch_course(scope, id),
         :ok <- Helpers.check_section(scope, course, input[:section_id]) do
      draft =
        Feed.get_draft(scope, course) || %Post{course_id: course.id, author_id: scope.user.id}

      with {:ok, draft} <-
             draft
             |> Post.draft_changeset(Map.take(input, [:body, :section_id]))
             |> Repo.insert_or_update(Tenancy.opts(scope)),
           :ok <- Feed.sync_attachments(scope, draft, course, input[:attachment_ids]) do
        {:ok, draft}
      end
    end
  end

  @impl true
  def audit(_scope, _input, _result), do: :skip
end

defmodule Amauta.Feed.Actions.PublishPost do
  @moduledoc """
  Publica en el tablón (RF-TAB-001 y 002), para todo el curso o una
  comisión. Si había un borrador, es el que se publica. Avisa en tiempo
  real a quienes miran el tablón.
  """
  use Amauta.Action,
    name: "feed.post.publish",
    description: "Publica en el tablón del curso.",
    params: [
      course_id: {Ecto.UUID, required: true},
      body: :string,
      section_id: Ecto.UUID,
      attachment_ids: {{:array, Ecto.UUID}, []}
    ]

  alias Amauta.Feed
  alias Amauta.Feed.Actions.Helpers
  alias Amauta.Feed.Post
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(scope, %{course_id: id} = input),
    do: Helpers.authorize_post(scope, id, input[:section_id])

  @impl true
  def run(scope, %{course_id: id} = input) do
    with {:ok, course} <- Helpers.fetch_course(scope, id),
         :ok <- Helpers.check_section(scope, course, input[:section_id]) do
      post =
        Feed.get_draft(scope, course) || %Post{course_id: course.id, author_id: scope.user.id}

      attrs = %{body: input[:body], section_id: input[:section_id]}

      with {:ok, post} <-
             post |> Post.publish_changeset(attrs) |> Repo.insert_or_update(Tenancy.opts(scope)),
           :ok <- Feed.sync_attachments(scope, post, course, input[:attachment_ids]) do
        {:ok, Repo.preload(post, [:author, :section, :course], force: true)}
      end
    end
  end

  @impl true
  def audit(_scope, input, post),
    do: {post, %{course_id: input.course_id, section_id: input[:section_id]}}

  # Avisos (RF-NOT-008): en segundo plano, a la audiencia de la publicación y
  # a quienes menciona.
  @impl true
  def effects(scope, _input, post) do
    [
      Amauta.Notifications.DeliverWorker.job(scope, "feed.post_published", %{"post_id" => post.id}),
      Amauta.Notifications.DeliverWorker.job(scope, "feed.mentioned", %{"post_id" => post.id})
    ]
  end

  @impl true
  def after_commit(_scope, _input, post) do
    Feed.broadcast(post.course, :published, post)
    :ok
  end
end

defmodule Amauta.Feed.Actions.UpdatePost do
  @moduledoc "Edita una publicación propia; queda la marca «editado» (RF-TAB-003)."
  use Amauta.Action,
    name: "feed.post.update",
    description: "Edita una publicación propia del tablón.",
    params: [
      post_id: {Ecto.UUID, required: true},
      body: {:string, required: true},
      attachment_ids: {{:array, Ecto.UUID}, []}
    ]

  alias Amauta.Feed
  alias Amauta.Feed.Post
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(%{user: %{id: user_id}} = scope, %{post_id: id}) do
    case Feed.get(scope, id) do
      nil ->
        {:error, :not_found}

      %{status: "published", author_id: ^user_id, course: %{status: status}}
      when status != "archived" ->
        :ok

      %{course: %{status: "archived"}} ->
        {:error, :archived}

      _ ->
        {:error, :forbidden}
    end
  end

  @impl true
  def run(scope, %{post_id: id, body: body} = input) do
    post = Feed.get(scope, id)

    with {:ok, updated} <-
           post |> Post.edit_changeset(%{body: body}) |> Repo.update(Tenancy.opts(scope)),
         :ok <- Feed.sync_attachments(scope, updated, post.course, input[:attachment_ids]) do
      {:ok, Repo.preload(updated, [:author, :section, :course], force: true)}
    end
  end

  @impl true
  def audit(_scope, _input, post), do: {post, %{course_id: post.course_id}}

  @impl true
  def after_commit(_scope, _input, post) do
    Feed.broadcast(post.course, :updated, post)
    :ok
  end
end

defmodule Amauta.Feed.Actions.DeletePost do
  @moduledoc """
  Elimina una publicación: la propia, o cualquiera si modera el tablón
  (RF-TAB-003 y 007).
  """
  use Amauta.Action,
    name: "feed.post.delete",
    description: "Elimina una publicación del tablón.",
    params: [post_id: {Ecto.UUID, required: true}]

  alias Amauta.Feed
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(%{user: %{id: user_id}} = scope, %{post_id: id}) do
    case Feed.get(scope, id) do
      nil -> {:error, :not_found}
      %{author_id: ^user_id} -> :ok
      post -> if Feed.can_moderate?(scope, post.course), do: :ok, else: {:error, :forbidden}
    end
  end

  @impl true
  def run(scope, %{post_id: id}) do
    post = Feed.get(scope, id)
    Feed.discard_attachments(scope, post)

    with {:ok, _} <- Repo.delete(post, Tenancy.opts(scope)), do: {:ok, post}
  end

  @impl true
  def audit(_scope, _input, post),
    do: {post, %{course_id: post.course_id, author_id: post.author_id}}

  @impl true
  def after_commit(_scope, _input, post) do
    Feed.broadcast(post.course, :deleted, post)
    :ok
  end
end

defmodule Amauta.Feed.Actions.ReplyToPost do
  @moduledoc """
  Responde a una publicación o a otra respuesta (RF-TAB-004). Un solo nivel
  de anidación: si se responde a una respuesta anidada, la nueva cuelga de
  la misma respuesta de primer nivel.
  """
  use Amauta.Action,
    name: "feed.reply.create",
    description: "Responde en el tablón.",
    params: [
      post_id: {Ecto.UUID, required: true},
      parent_id: Ecto.UUID,
      body: :string,
      attachment_ids: {{:array, Ecto.UUID}, []}
    ]

  alias Amauta.Feed
  alias Amauta.Feed.Reply
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(scope, %{post_id: id}) do
    with %{course: course} = post <- Feed.get(scope, id) || {:error, :not_found},
         %{} <- Feed.get_visible(scope, course, id) || {:error, :not_found},
         true <-
           (Feed.can_reply?(scope, course) and Feed.replies_open?(post)) || {:error, :forbidden} do
      :ok
    end
  end

  @impl true
  def run(scope, %{post_id: id} = input) do
    with {:ok, parent_id} <- parent(scope, id, input[:parent_id]),
         {:ok, reply} <-
           %Reply{post_id: id, author_id: scope.user.id, parent_id: parent_id}
           |> Reply.create_changeset(%{body: input[:body]})
           |> Repo.insert(Tenancy.opts(scope)),
         reply = Repo.preload(reply, post: :course),
         :ok <- Feed.sync_attachments(scope, reply, reply.post.course, input[:attachment_ids]) do
      {:ok, reply}
    end
  end

  # La respuesta padre tiene que ser de la misma publicación; se aplana a
  # un solo nivel.
  defp parent(_scope, _post_id, nil), do: {:ok, nil}

  defp parent(scope, post_id, parent_id) do
    case Feed.get_reply(scope, parent_id) do
      %{post_id: ^post_id, parent_id: nil, id: id} -> {:ok, id}
      %{post_id: ^post_id, parent_id: top} -> {:ok, top}
      _ -> {:error, :not_found}
    end
  end

  @impl true
  def audit(_scope, _input, reply), do: {reply, %{post_id: reply.post_id}}

  # Avisos: a quien publicó, a quienes participan y a quienes menciona.
  @impl true
  def effects(scope, _input, reply) do
    [
      Amauta.Notifications.DeliverWorker.job(scope, "feed.reply_created", %{
        "reply_id" => reply.id
      }),
      Amauta.Notifications.DeliverWorker.job(scope, "feed.mentioned", %{
        "post_id" => reply.post_id,
        "reply_id" => reply.id
      })
    ]
  end

  @impl true
  def after_commit(_scope, _input, reply) do
    Feed.broadcast(reply.post.course, :updated, reply.post)
    :ok
  end
end

defmodule Amauta.Feed.Actions.UpdateReply do
  @moduledoc "Edita una respuesta propia; queda la marca de editada."
  use Amauta.Action,
    name: "feed.reply.update",
    description: "Edita una respuesta propia del tablón.",
    params: [
      reply_id: {Ecto.UUID, required: true},
      body: {:string, required: true},
      attachment_ids: {{:array, Ecto.UUID}, []}
    ]

  alias Amauta.Feed
  alias Amauta.Feed.Reply
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(%{user: %{id: user_id}} = scope, %{reply_id: id}) do
    case Feed.get_reply(scope, id) do
      nil -> {:error, :not_found}
      %{post: %{course: %{status: "archived"}}} -> {:error, :archived}
      %{author_id: ^user_id} -> :ok
      _ -> {:error, :forbidden}
    end
  end

  @impl true
  def run(scope, %{reply_id: id, body: body} = input) do
    reply = Feed.get_reply(scope, id)

    with {:ok, updated} <-
           reply |> Reply.edit_changeset(%{body: body}) |> Repo.update(Tenancy.opts(scope)),
         :ok <- Feed.sync_attachments(scope, updated, reply.post.course, input[:attachment_ids]) do
      {:ok, %{updated | post: reply.post}}
    end
  end

  @impl true
  def audit(_scope, _input, reply), do: {reply, %{post_id: reply.post_id}}

  @impl true
  def after_commit(_scope, _input, reply) do
    Feed.broadcast(reply.post.course, :updated, reply.post)
    :ok
  end
end

defmodule Amauta.Feed.Actions.DeleteReply do
  @moduledoc "Elimina una respuesta: la propia, o cualquiera si modera (RF-TAB-007)."
  use Amauta.Action,
    name: "feed.reply.delete",
    description: "Elimina una respuesta del tablón.",
    params: [reply_id: {Ecto.UUID, required: true}]

  alias Amauta.Feed
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(%{user: %{id: user_id}} = scope, %{reply_id: id}) do
    case Feed.get_reply(scope, id) do
      nil ->
        {:error, :not_found}

      %{author_id: ^user_id} ->
        :ok

      reply ->
        if Feed.can_moderate?(scope, reply.post.course), do: :ok, else: {:error, :forbidden}
    end
  end

  @impl true
  def run(scope, %{reply_id: id}) do
    reply = Feed.get_reply(scope, id)
    Feed.discard_attachments(scope, reply)
    with {:ok, _} <- Repo.delete(reply, Tenancy.opts(scope)), do: {:ok, reply}
  end

  @impl true
  def audit(_scope, _input, reply),
    do: {reply, %{post_id: reply.post_id, author_id: reply.author_id}}

  @impl true
  def after_commit(_scope, _input, reply) do
    Feed.broadcast(reply.post.course, :updated, reply.post)
    :ok
  end
end

defmodule Amauta.Feed.Actions.HideReply do
  @moduledoc """
  Oculta o vuelve a mostrar una respuesta (moderación, RF-TAB-007). Oculta,
  el resto ve que hay una respuesta oculta; el contenido no se borra.
  """
  use Amauta.Action,
    name: "feed.reply.hide",
    description: "Oculta o muestra una respuesta del tablón.",
    params: [reply_id: {Ecto.UUID, required: true}, hidden: {:boolean, required: true}]

  alias Amauta.Feed
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(scope, %{reply_id: id}) do
    case Feed.get_reply(scope, id) do
      nil ->
        {:error, :not_found}

      reply ->
        if Feed.can_moderate?(scope, reply.post.course), do: :ok, else: {:error, :forbidden}
    end
  end

  @impl true
  def run(scope, %{reply_id: id, hidden: hidden}) do
    reply = Feed.get_reply(scope, id)

    changes =
      if hidden,
        do: [hidden_at: DateTime.utc_now(), hidden_by_id: scope.user.id],
        else: [hidden_at: nil, hidden_by_id: nil]

    with {:ok, updated} <-
           reply |> Ecto.Changeset.change(changes) |> Repo.update(Tenancy.opts(scope)) do
      {:ok, %{updated | post: reply.post}}
    end
  end

  @impl true
  def audit(_scope, %{hidden: hidden}, reply),
    do: {reply, %{post_id: reply.post_id, hidden: hidden}}

  @impl true
  def after_commit(_scope, _input, reply) do
    Feed.broadcast(reply.post.course, :updated, reply.post)
    :ok
  end
end

defmodule Amauta.Feed.Actions.SetRepliesEnabled do
  @moduledoc "Abre o cierra las respuestas de una publicación (RF-TAB-004): su autor o quien modera."
  use Amauta.Action,
    name: "feed.post.set_replies",
    description: "Abre o cierra las respuestas de una publicación.",
    params: [post_id: {Ecto.UUID, required: true}, enabled: {:boolean, required: true}]

  alias Amauta.Feed
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(%{user: %{id: user_id}} = scope, %{post_id: id}) do
    case Feed.get(scope, id) do
      nil -> {:error, :not_found}
      %{author_id: ^user_id} -> :ok
      post -> if Feed.can_moderate?(scope, post.course), do: :ok, else: {:error, :forbidden}
    end
  end

  @impl true
  def run(scope, %{post_id: id, enabled: enabled}) do
    post = Feed.get(scope, id)

    with {:ok, updated} <-
           post
           |> Ecto.Changeset.change(replies_enabled: enabled)
           |> Repo.update(Tenancy.opts(scope)) do
      {:ok, %{updated | course: post.course}}
    end
  end

  @impl true
  def after_commit(_scope, _input, post) do
    Feed.broadcast(post.course, :updated, post)
    :ok
  end
end

defmodule Amauta.Feed.Actions.MuteMember do
  @moduledoc """
  Silencia (o deja de silenciar) a una persona en el tablón del curso
  (RF-TAB-007): no puede publicar ni responder ahí. No se puede silenciar a
  quien también modera, ni a uno mismo.
  """
  use Amauta.Action,
    name: "feed.member.mute",
    description: "Silencia a una persona en el tablón del curso.",
    params: [
      course_id: {Ecto.UUID, required: true},
      user_id: {Ecto.UUID, required: true},
      muted: {:boolean, required: true}
    ]

  import Ecto.Query

  alias Amauta.Feed.Mute
  alias Amauta.{Accounts, Courses, Feed, Repo, Scope, Tenancy}

  @impl true
  def authorize(%{user: %{id: id}}, %{user_id: id}), do: {:error, :forbidden}

  def authorize(scope, %{course_id: course_id, user_id: user_id}) do
    with %{} = course <- Courses.get(scope, course_id) || {:error, :not_found},
         true <- Feed.can_moderate?(scope, course) || {:error, :forbidden},
         %{} = user <-
           Repo.get(Accounts.User, user_id, Tenancy.opts(scope)) || {:error, :not_found} do
      if Feed.can_moderate?(Scope.for_user(scope.institution, user), course),
        do: {:error, :forbidden},
        else: :ok
    end
  end

  @impl true
  def run(scope, %{course_id: course_id, user_id: user_id, muted: true}) do
    %Mute{course_id: course_id, user_id: user_id, muted_by_id: scope.user.id}
    |> Repo.insert(Keyword.merge(Tenancy.opts(scope), on_conflict: :nothing))
  end

  def run(scope, %{course_id: course_id, user_id: user_id, muted: false}) do
    from(m in Mute, where: m.course_id == ^course_id and m.user_id == ^user_id)
    |> Repo.delete_all(Tenancy.opts(scope))

    {:ok, %{course_id: course_id, user_id: user_id}}
  end

  @impl true
  def audit(_scope, input, _result), do: {nil, input}
end

defmodule Amauta.Feed.Actions.PinPost do
  @moduledoc """
  Fija o desfija una publicación (RF-TAB-006), con vencimiento opcional:
  vencida, deja de estar fijada sola. Una nueva va al final de las fijadas;
  cambiar el vencimiento de una ya fijada no la mueve. Lo hace quien modera.
  """
  use Amauta.Action,
    name: "feed.post.pin",
    description: "Fija o desfija una publicación del tablón.",
    params: [
      post_id: {Ecto.UUID, required: true},
      pinned: {:boolean, required: true},
      expires_at: :utc_datetime_usec
    ]

  import Ecto.Query

  alias Amauta.Feed
  alias Amauta.Feed.Post
  alias Amauta.{Repo, Tenancy}

  @impl true
  def validate(changeset) do
    Ecto.Changeset.validate_change(changeset, :expires_at, fn :expires_at, expires ->
      if DateTime.compare(expires, DateTime.utc_now()) == :gt,
        do: [],
        else: [expires_at: "must be in the future"]
    end)
  end

  @impl true
  def authorize(scope, %{post_id: id}) do
    with %{course: course} = post <- Feed.get(scope, id) || {:error, :not_found},
         true <- post.status == "published" || {:error, :not_found},
         true <- course.status != "archived" || {:error, :archived} do
      if Feed.can_moderate?(scope, course), do: :ok, else: {:error, :forbidden}
    end
  end

  @impl true
  def run(scope, %{post_id: id, pinned: true} = input) do
    post = Feed.get(scope, id)
    now = DateTime.utc_now()

    changes =
      if Feed.pinned?(post, now),
        do: [pin_expires_at: input[:expires_at]],
        else: [
          pinned_at: now,
          pinned_by_id: scope.user.id,
          pin_expires_at: input[:expires_at],
          pin_position: next_position(scope, post.course_id)
        ]

    save(scope, post, changes)
  end

  def run(scope, %{post_id: id, pinned: false}) do
    post = Feed.get(scope, id)
    save(scope, post, pinned_at: nil, pinned_by_id: nil, pin_expires_at: nil, pin_position: nil)
  end

  defp save(scope, post, changes) do
    with {:ok, updated} <-
           post |> Ecto.Changeset.change(changes) |> Repo.update(Tenancy.opts(scope)) do
      {:ok, %{updated | course: post.course}}
    end
  end

  defp next_position(scope, course_id) do
    from(p in Post, where: p.course_id == ^course_id, select: max(p.pin_position))
    |> Repo.one(Tenancy.opts(scope))
    |> Kernel.||(0)
    |> Kernel.+(1)
  end

  @impl true
  def audit(_scope, input, post),
    do: {post, Map.take(input, [:pinned, :expires_at])}

  @impl true
  def after_commit(_scope, _input, post) do
    Feed.broadcast(post.course, :pinned, post)
    :ok
  end
end

defmodule Amauta.Feed.Actions.ReorderPinned do
  @moduledoc """
  Ordena a mano las publicaciones fijadas de un curso (RF-TAB-006). Recibe
  los IDs en el orden nuevo; las fijadas que falten quedan al final, en su
  orden anterior, y lo que no esté fijado se ignora.
  """
  use Amauta.Action,
    name: "feed.post.reorder_pins",
    description: "Ordena las publicaciones fijadas del tablón.",
    params: [
      course_id: {Ecto.UUID, required: true},
      post_ids: {{:array, Ecto.UUID}, required: true}
    ]

  import Ecto.Query

  alias Amauta.Feed.Post
  alias Amauta.{Courses, Feed, Repo, Tenancy}

  @impl true
  def authorize(scope, %{course_id: id}) do
    case Courses.get(scope, id) do
      nil -> {:error, :not_found}
      %{status: "archived"} -> {:error, :archived}
      course -> if Feed.can_moderate?(scope, course), do: :ok, else: {:error, :forbidden}
    end
  end

  @impl true
  def run(scope, %{course_id: id, post_ids: ids}) do
    course = Courses.get(scope, id)
    current = Feed.pinned_ids(scope, course)
    order = Enum.filter(Enum.uniq(ids), &(&1 in current)) ++ (current -- ids)

    order
    |> Enum.with_index(1)
    |> Enum.each(fn {post_id, position} ->
      from(p in Post, where: p.id == ^post_id)
      |> Repo.update_all([set: [pin_position: position]], Tenancy.opts(scope))
    end)

    {:ok, %{course: course, post_ids: order}}
  end

  @impl true
  def audit(_scope, _input, %{course: course, post_ids: ids}),
    do: {course, %{post_ids: ids}}

  @impl true
  def after_commit(_scope, _input, %{course: course}) do
    Feed.broadcast(course, :pinned, nil)
    :ok
  end
end
