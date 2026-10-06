defmodule AmautaWeb.FeedLive do
  @moduledoc "Tablón de un curso, en tiempo real."
  use AmautaWeb, :live_view

  alias Amauta.{Catalog, Feed}
  alias Amauta.Feed.Post

  @impl true
  def mount(%{"course" => slug}, _session, socket) do
    scope = socket.assigns.current_scope
    course = Catalog.get_course_by_slug!(slug, scope: scope) || raise AmautaWeb.NotFoundError

    posts =
      case Feed.list_posts(course.id, scope: scope) do
        {:ok, posts} -> posts
        {:error, %Ash.Error.Forbidden{}} -> raise AmautaWeb.ForbiddenError
      end

    if connected?(socket), do: Feed.subscribe(scope.institution, course)

    {:ok,
     socket
     |> assign(:course, course)
     |> assign(:can_post, Ash.can?({Post, :create, %{course_id: course.id}}, scope))
     |> assign_form()
     |> stream(:posts, posts)}
  end

  @impl true
  def handle_event("validate", %{"post" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"post" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _post} -> {:noreply, assign_form(socket)}
      {:error, form} -> {:noreply, assign(socket, :form, form)}
    end
  end

  @impl true
  def handle_info({"create", %Ash.Notifier.Notification{data: post}}, socket) do
    {:noreply, stream_insert(socket, :posts, post, at: 0)}
  end

  defp assign_form(socket) do
    %{course: course, current_scope: scope} = socket.assigns

    form =
      Post
      |> AshPhoenix.Form.for_create(:create,
        as: "post",
        scope: scope,
        transform_params: fn _form, params, _type -> Map.put(params, "course_id", course.id) end
      )
      |> to_form()

    assign(socket, :form, form)
  end

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
