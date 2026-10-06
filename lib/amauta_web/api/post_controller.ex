defmodule AmautaWeb.Api.PostController do
  @moduledoc "Tablón por API. Usa las mismas acciones que la interfaz."
  use AmautaWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Amauta.Actions
  alias Amauta.Feed.Actions.{CreatePost, ListPosts}
  alias AmautaWeb.Api.Schemas

  action_fallback AmautaWeb.Api.FallbackController

  tags ["feed"]

  @course_id [in: :path, type: :string, required: true, description: "ID del curso"]
  @errors [
    unauthorized: {"Sin autenticar", "application/json", Schemas.Error},
    forbidden: {"Sin permiso", "application/json", Schemas.Error},
    not_found: {"Curso inexistente", "application/json", Schemas.Error}
  ]

  operation :index,
    operation_id: ListPosts.name(),
    summary: "Lista las publicaciones del tablón",
    parameters: [course_id: @course_id],
    responses: [ok: {"Publicaciones", "application/json", Schemas.PostListResponse}] ++ @errors

  def index(conn, %{"course_id" => course_id}) do
    scope = conn.assigns.current_scope

    with {:ok, posts} <- Actions.run(ListPosts, scope, %{"course_id" => course_id}) do
      json(conn, %{data: Enum.map(posts, &post_json/1)})
    end
  end

  operation :create,
    operation_id: CreatePost.name(),
    summary: "Publica en el tablón",
    parameters: [course_id: @course_id],
    request_body: {"Publicación", "application/json", Schemas.PostParams, required: true},
    responses:
      [
        created: {"Publicación creada", "application/json", Schemas.PostResponse},
        unprocessable_entity: {"Datos inválidos", "application/json", Schemas.Error}
      ] ++ @errors

  def create(conn, %{"course_id" => course_id} = params) do
    params = %{"course_id" => course_id, "body" => params["body"]}

    with {:ok, post} <- Actions.run(CreatePost, conn.assigns.current_scope, params) do
      conn |> put_status(:created) |> json(%{data: post_json(post)})
    end
  end

  defp post_json(post) do
    %{
      id: post.id,
      body: post.body,
      author: %{id: post.author.id, name: post.author.name},
      inserted_at: post.inserted_at
    }
  end
end
