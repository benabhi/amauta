defmodule AmautaWeb.FeedLive do
  @moduledoc "Tablón de un curso, en tiempo real."
  use AmautaWeb, :live_view

  alias Amauta.{Actions, Authorization, Catalog, Feed}
  alias Amauta.Feed.Actions.{CreatePost, ListPosts}
  alias Amauta.Feed.Post

  @impl true
  def mount(%{"course" => slug}, _session, socket) do
    scope = socket.assigns.current_scope
    course = Catalog.get_course_by_slug(scope, slug) || raise AmautaWeb.NotFoundError

    posts =
      case Actions.run(ListPosts, scope, %{"course_id" => course.id}) do
        {:ok, posts} -> posts
        {:error, :forbidden} -> raise AmautaWeb.ForbiddenError
      end

    if connected?(socket), do: Feed.subscribe(scope, course)

    {:ok,
     socket
     |> assign(:course, course)
     |> assign(:can_post, Authorization.can?(scope, "course.feed.post", course))
     |> assign_form(Post.changeset(%Post{}, %{}))
     |> stream(:posts, posts)}
  end

  @impl true
  def handle_event("validate", %{"post" => params}, socket) do
    changeset = %Post{} |> Post.changeset(params) |> Map.put(:action, :validate)
    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"post" => params}, socket) do
    params = Map.put(params, "course_id", socket.assigns.course.id)

    case Actions.run(CreatePost, socket.assigns.current_scope, params) do
      {:ok, _post} ->
        {:noreply, assign_form(socket, Post.changeset(%Post{}, %{}))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("You can't post in this course."))}
    end
  end

  @impl true
  def handle_info({:post_created, post}, socket) do
    {:noreply, stream_insert(socket, :posts, post, at: 0)}
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@course.name}
        <:subtitle>{gettext("Board")}</:subtitle>
      </.header>

      <.form :if={@can_post} for={@form} id="post-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:body]} type="textarea" label={gettext("New post")} />
        <.button phx-disable-with={gettext("Posting...")}>{gettext("Post")}</.button>
      </.form>

      <div id="posts" phx-update="stream" class="mt-8 space-y-4">
        <article :for={{id, post} <- @streams.posts} id={id} class="rounded border p-4">
          <p class="font-semibold">{post.author.name}</p>
          <p class="whitespace-pre-line">{post.body}</p>
        </article>
      </div>
    </Layouts.app>
    """
  end
end
