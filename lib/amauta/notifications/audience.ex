defmodule Amauta.Notifications.Audience do
  @moduledoc """
  A quién le llega cada evento y por qué (RF-NOT-002). Devuelve
  `{[{user_id, reason}], attrs}` para `Amauta.Notifications.deliver/4`, o
  `nil` si lo que lo originó ya no existe.

  Motivos (`reason`): `role:<rol>` (por ser parte del curso con ese rol),
  `mentioned`, `post_author`, `thread_participant` y `enrolled`.
  """
  import Ecto.Query

  alias Amauta.Content.Item
  alias Amauta.Enrollments.Enrollment
  alias Amauta.Feed.{Post, Reply}
  alias Amauta.{Repo, RichText, Tenancy}

  def build(tenant, "feed.post_published", %{"post_id" => id}) do
    with %Post{status: "published", kind: "post"} = post <- get(tenant, Post, id, [:course]) do
      mentioned = RichText.mentions(post.body)

      recipients =
        for e <- members(tenant, post.course_id, post.section_id),
            e.user_id not in mentioned,
            do: {e.user_id, "role:" <> e.role}

      {recipients, post_attrs(post, "post:#{post.id}")}
    end
  end

  # Menciones en una publicación o en una respuesta: solo a quien la puede ver.
  def build(tenant, "feed.mentioned", %{"post_id" => id} = args) do
    with %Post{status: "published"} = post <- get(tenant, Post, id, [:course]),
         {:ok, body, actor_id} <- mention_source(tenant, post, args["reply_id"]) do
      visible = MapSet.new(members(tenant, post.course_id, post.section_id), & &1.user_id)

      recipients =
        for user_id <- RichText.mentions(body),
            MapSet.member?(visible, user_id),
            do: {user_id, "mentioned"}

      attrs = %{post_attrs(post, "mention:#{post.id}:#{args["reply_id"]}") | actor_id: actor_id}
      {recipients, attrs}
    end
  end

  # Respuestas: a quien publicó y a quienes ya participaron, salvo los que
  # la respuesta menciona (a ellos les llega la mención).
  def build(tenant, "feed.reply_created", %{"reply_id" => id}) do
    with %Reply{} = reply <- get(tenant, Reply, id, post: :course),
         %Post{status: "published"} = post <- reply.post do
      opts = Tenancy.opts(tenant)
      mentioned = RichText.mentions(reply.body)
      visible = MapSet.new(members(tenant, post.course_id, post.section_id), & &1.user_id)

      participants =
        from(r in Reply,
          where: r.post_id == ^post.id and r.id != ^reply.id and not is_nil(r.author_id),
          distinct: true,
          select: r.author_id
        )
        |> Repo.all(opts)

      recipients =
        [{post.author_id, "post_author"} | Enum.map(participants, &{&1, "thread_participant"})]
        |> Enum.filter(fn {user_id, _} ->
          (user_id && user_id not in mentioned) and MapSet.member?(visible, user_id)
        end)

      attrs = %{post_attrs(post, "replies:#{post.id}") | actor_id: reply.author_id}
      {recipients, attrs}
    end
  end

  def build(tenant, "content.item_published", %{"item_id" => id}) do
    with %Item{} = item <- get(tenant, Item, id, []) do
      recipients =
        for e <- members(tenant, item.course_id, nil), do: {e.user_id, "role:" <> e.role}

      {recipients,
       %{
         course_id: item.course_id,
         actor_id: item.created_by_id,
         group_key: "content:#{item.id}",
         data: %{"item_id" => item.id, "title" => item.title, "kind" => item.kind}
       }}
    end
  end

  def build(tenant, "enrollment.created", %{"enrollment_id" => id}) do
    with %Enrollment{status: "active"} = enrollment <- get(tenant, Enrollment, id, []) do
      {[{enrollment.user_id, "enrolled"}],
       %{
         course_id: enrollment.course_id,
         actor_id: enrollment.enrolled_by_id,
         group_key: "enrollment:#{enrollment.id}",
         data: %{"role" => enrollment.role}
       }}
    end
  end

  def build(_tenant, _event, _args), do: nil

  defp mention_source(_tenant, post, nil), do: {:ok, post.body, post.author_id}

  defp mention_source(tenant, post, reply_id) do
    case get(tenant, Reply, reply_id, []) do
      %Reply{post_id: post_id} = reply when post_id == post.id ->
        {:ok, reply.body, reply.author_id}

      _ ->
        nil
    end
  end

  defp post_attrs(post, group_key) do
    %{
      course_id: post.course_id,
      actor_id: post.author_id,
      group_key: group_key,
      data: %{"post_id" => post.id, "title" => excerpt(post.body)}
    }
  end

  defp excerpt(body) do
    body
    |> RichText.to_text()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, 120)
  end

  # Matrículas activas del curso; con comisión, solo quienes la ven: su
  # estudiantado y el equipo docente del curso entero o de esa comisión.
  defp members(tenant, course_id, section_id) do
    from(e in Enrollment, where: e.course_id == ^course_id and e.status == "active")
    |> then(fn query ->
      if section_id,
        do: where(query, [e], is_nil(e.section_id) or e.section_id == ^section_id),
        else: query
    end)
    |> Repo.all(Tenancy.opts(tenant))
    |> Enum.filter(
      &(is_nil(section_id) or &1.section_id == section_id or
          &1.role in Enrollment.teaching_roles())
    )
  end

  defp get(tenant, schema, id, preloads) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %{} = struct <- Repo.get(schema, id, Tenancy.opts(tenant)) do
      Repo.preload(struct, preloads, Tenancy.opts(tenant))
    else
      _ -> nil
    end
  end
end
