defmodule Amauta.Feed.Actions.CreatePost do
  @moduledoc "Publica en el tablón de un curso (RF-TAB-001, versión mínima)."
  use Amauta.Action, name: "feed.post.create", permission: "course.feed.post"
  alias Amauta.{Catalog, Feed, Repo, Tenancy}
  alias Amauta.Feed.Post

  @impl true
  def load(scope, %{"course_id" => id}) do
    case Catalog.get_course(scope, id) do
      nil -> {:error, :not_found}
      course -> {:ok, course}
    end
  end

  @impl true
  def execute(scope, course, params) do
    %Post{course_id: course.id, author_id: scope.user.id}
    |> Post.changeset(params)
    |> Repo.insert(Tenancy.opts(scope))
    |> case do
      {:ok, post} -> {:ok, %{post | author: scope.user}}
      error -> error
    end
  end

  @impl true
  def after_commit(scope, course, post) do
    Feed.broadcast(scope, course, {:post_created, post})
  end
end
