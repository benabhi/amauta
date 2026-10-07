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
      section_id: Ecto.UUID
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

      draft
      |> Post.draft_changeset(Map.take(input, [:body, :section_id]))
      |> Repo.insert_or_update(Tenancy.opts(scope))
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
      section_id: Ecto.UUID
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
             post |> Post.publish_changeset(attrs) |> Repo.insert_or_update(Tenancy.opts(scope)) do
        {:ok, Repo.preload(post, [:author, :section, :course], force: true)}
      end
    end
  end

  @impl true
  def audit(_scope, input, post),
    do: {post, %{course_id: input.course_id, section_id: input[:section_id]}}

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
    params: [post_id: {Ecto.UUID, required: true}, body: {:string, required: true}]

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
  def run(scope, %{post_id: id, body: body}) do
    with {:ok, post} <-
           scope
           |> Feed.get(id)
           |> Post.edit_changeset(%{body: body})
           |> Repo.update(Tenancy.opts(scope)) do
      {:ok, Repo.preload(post, [:author, :section, :course], force: true)}
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
