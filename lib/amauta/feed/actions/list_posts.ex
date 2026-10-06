defmodule Amauta.Feed.Actions.ListPosts do
  @moduledoc "Lista las publicaciones del tablón de un curso."
  use Amauta.Action, name: "feed.post.list", permission: "course.view", audit: false
  alias Amauta.{Catalog, Feed}

  @impl true
  def load(scope, %{"course_id" => id}), do: found(Catalog.get_course(scope, id))
  def load(scope, %{"course_slug" => slug}), do: found(Catalog.get_course_by_slug(scope, slug))

  @impl true
  def execute(scope, course, _params), do: {:ok, Feed.list_posts(scope, course)}

  defp found(nil), do: {:error, :not_found}
  defp found(course), do: {:ok, course}
end
