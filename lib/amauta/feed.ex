defmodule Amauta.Feed do
  @moduledoc """
  Tablón. Las operaciones son acciones (`Amauta.Feed.Actions.*`); este
  módulo tiene las consultas y la suscripción en tiempo real.
  """
  import Ecto.Query
  alias Amauta.Feed.Post
  alias Amauta.{Repo, Tenancy}

  def list_posts(tenant, course) do
    from(p in Post,
      where: p.course_id == ^course.id,
      order_by: [desc: p.inserted_at],
      preload: :author
    )
    |> Repo.all(Tenancy.opts(tenant))
  end

  def topic(tenant, course), do: "feed:#{Tenancy.prefix(tenant)}:#{course.id}"

  def subscribe(tenant, course),
    do: Phoenix.PubSub.subscribe(Amauta.PubSub, topic(tenant, course))

  def broadcast(tenant, course, message) do
    Phoenix.PubSub.broadcast(Amauta.PubSub, topic(tenant, course), message)
  end
end
