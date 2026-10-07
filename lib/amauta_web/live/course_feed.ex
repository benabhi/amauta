defmodule AmautaWeb.CourseFeed do
  @moduledoc """
  Tablón del curso (RF-TAB-001 a 003, 007 y 008), dentro de la pestaña
  Tablón de `AmautaWeb.CourseLive`.

  Quien puede publicar ve el editor arriba, con su borrador guardado
  mientras escribe y el destinatario (todo el curso o una comisión). Las
  publicaciones nuevas llegan en tiempo real: la vista del curso escucha el
  tema del tablón y se las pasa a este componente (`send_update/2`). Si la
  persona está leyendo más abajo, aparece «N publicaciones nuevas» en lugar
  de mover la página.
  """
  use AmautaWeb, :live_component

  alias Amauta.Accounts.User
  alias Amauta.{Actions, Feed}
  alias Amauta.Feed.Actions.{DeletePost, PublishPost, SaveDraft, UpdatePost}
  alias AmautaWeb.{Format, Paths}

  @impl true
  def mount(socket),
    do: {:ok, assign(socket, editor_key: 0, editing: nil, edit_form: nil, loaded: false)}

  @impl true
  def update(%{feed_event: {event, post}}, socket), do: {:ok, apply_event(socket, event, post)}

  def update(assigns, socket) do
    %{current_scope: scope, course: course} = assigns
    filter_changed = assigns.section_filter != socket.assigns[:section_filter]

    socket =
      socket
      |> assign(assigns)
      |> assign(
        can_post: Feed.can_post?(scope, course),
        can_moderate: Feed.can_moderate?(scope, course),
        timezone: scope.user.timezone || scope.institution.timezone
      )

    socket =
      if socket.assigns.loaded and not filter_changed,
        do: socket,
        else: load(socket)

    {:ok, socket}
  end

  defp load(socket) do
    %{current_scope: scope, course: course, section_filter: filter} = socket.assigns
    posts = Feed.list_posts(scope, course, %{"section" => filter})

    socket
    |> assign(loaded: true, empty: posts == [])
    |> stream(:posts, posts, reset: true)
    |> assign_composer()
  end

  defp assign_composer(%{assigns: %{can_post: false}} = socket),
    do: assign(socket, form: nil, targets: [])

  defp assign_composer(socket) do
    %{current_scope: scope, course: course, sections: sections} = socket.assigns
    draft = Feed.get_draft(scope, course)

    targets =
      case Feed.targetable_sections(scope, course) do
        :any -> [nil | Enum.map(sections, & &1.id)]
        allowed -> allowed
      end

    section =
      (draft && draft.section_id) || default_target(targets, socket.assigns.section_filter)

    assign(socket,
      targets: targets,
      form: to_form(%{"body" => draft && draft.body, "section_id" => section}, as: "post")
    )
  end

  # Por defecto, el curso entero; si no se puede, la comisión del filtro o
  # la primera permitida.
  defp default_target(targets, filter) do
    cond do
      nil in targets -> nil
      filter in targets -> filter
      true -> List.first(targets)
    end
  end

  # Llega algo del tablón en tiempo real: se muestra solo si esta persona lo
  # puede ver (y si coincide con el filtro de comisión).
  defp apply_event(socket, :deleted, post), do: stream_delete(socket, :posts, post)

  defp apply_event(socket, event, post) do
    %{current_scope: scope, course: course, section_filter: filter} = socket.assigns

    case Feed.get_visible(scope, course, post.id) do
      nil ->
        socket

      visible ->
        if filter not in [nil, ""] and visible.section_id not in [nil, filter] do
          socket
        else
          socket =
            stream_insert(socket, :posts, visible, at: if(event == :published, do: 0, else: -1))

          socket = assign(socket, empty: false)

          if event == :published and visible.author_id != scope.user.id,
            do: push_event(socket, "feed:new", %{}),
            else: socket
        end
    end
  end

  @impl true
  def handle_event("draft", %{"post" => params}, socket) do
    params = Map.put(params, "course_id", socket.assigns.course.id)
    Actions.run(SaveDraft, socket.assigns.current_scope, params)
    {:noreply, assign(socket, form: to_form(params, as: "post"))}
  end

  def handle_event("publish", %{"post" => params}, socket) do
    params = Map.put(params, "course_id", socket.assigns.course.id)

    case Actions.run(PublishPost, socket.assigns.current_scope, params) do
      {:ok, _post} ->
        # La publicación llega por el tema del tablón; acá se vacía el editor.
        {:noreply,
         socket
         |> update(:editor_key, &(&1 + 1))
         |> assign(form: to_form(%{"section_id" => params["section_id"]}, as: "post"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        message = changeset.errors |> Keyword.values() |> List.first() |> translate_error()
        {:noreply, put_flash_message(socket, message)}

      {:error, _} ->
        {:noreply, put_flash_message(socket, gettext("That could not be done."))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case Feed.get_visible(socket.assigns.current_scope, socket.assigns.course, id) do
      nil ->
        {:noreply, socket}

      post ->
        {:noreply,
         socket
         |> assign(editing: post.id, edit_form: to_form(%{"body" => post.body}, as: "edit"))
         |> stream_insert(:posts, post)}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    post =
      Feed.get_visible(
        socket.assigns.current_scope,
        socket.assigns.course,
        socket.assigns.editing
      )

    socket = assign(socket, editing: nil, edit_form: nil)
    {:noreply, if(post, do: stream_insert(socket, :posts, post), else: socket)}
  end

  def handle_event("save_edit", %{"edit" => %{"body" => body}}, socket) do
    params = %{"post_id" => socket.assigns.editing, "body" => body}

    case Actions.run(UpdatePost, socket.assigns.current_scope, params) do
      {:ok, post} ->
        {:noreply, socket |> assign(editing: nil, edit_form: nil) |> stream_insert(:posts, post)}

      {:error, _} ->
        {:noreply, put_flash_message(socket, gettext("That could not be done."))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Actions.run(DeletePost, socket.assigns.current_scope, %{"post_id" => id}) do
      {:ok, _post} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash_message(socket, gettext("That could not be done."))}
    end
  end

  # Los avisos van a la vista del curso, que es la que muestra los flash.
  defp put_flash_message(socket, message) do
    send(self(), {:put_flash, :error, message})
    socket
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="grid gap-6">
      <.card :if={@form} id="feed-composer-card">
        <.form
          for={@form}
          id="feed-composer"
          phx-change="draft"
          phx-submit="publish"
          phx-target={@myself}
        >
          <.rich_text_editor
            id={"feed-editor-#{@editor_key}"}
            field={@form[:body]}
            label={gettext("New post")}
            placeholder={gettext_term(@current_scope, :course, "Share something with the %{term}…")}
            debounce="1000"
          />
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div :if={length(@targets) > 1} class="w-60">
              <.input
                field={@form[:section_id]}
                type="select"
                aria-label={gettext("Audience")}
                options={target_options(@current_scope, @targets, @sections)}
              />
            </div>
            <.button
              icon="paper-plane-tilt"
              phx-disable-with={gettext("Publishing...")}
              class="ms-auto"
            >
              {gettext("Publish")}
            </.button>
          </div>
        </.form>
      </.card>

      <div id={"#{@id}-new"} phx-hook=".FeedNewPosts" class="relative">
        <button
          type="button"
          data-new-posts
          hidden
          data-one={gettext("1 new post")}
          data-other={gettext("%{count} new posts", count: "%{count}")}
          class="sticky top-16 z-30 mx-auto mb-2 flex min-h-11 items-center gap-2 rounded-full bg-primary px-4 text-sm font-semibold text-on-primary shadow-md"
        >
          <.icon name="arrow-up" class="size-4" /> <span data-new-posts-text></span>
        </button>

        <.empty_state :if={@empty} icon="chats-circle" title={gettext("Nothing posted yet")}>
          {gettext_term(
            @current_scope,
            :course,
            "Announcements and conversations of the %{term} will appear here."
          )}
        </.empty_state>

        <ol id="feed-posts" phx-update="stream" class="grid gap-4" aria-label={gettext("Feed")}>
          <li :for={{dom_id, post} <- @streams.posts} id={dom_id}>
            <.post
              post={post}
              current_scope={@current_scope}
              timezone={@timezone}
              can_moderate={@can_moderate}
              editing={@editing == post.id}
              edit_form={@edit_form}
              myself={@myself}
            />
          </li>
        </ol>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".FeedNewPosts">
        // Publicaciones nuevas en tiempo real (RF-TAB-008): si la persona está
        // leyendo más abajo, no se mueve la página; se avisa con un botón.
        export default {
          mounted() {
            this.count = 0
            this.button = this.el.querySelector("[data-new-posts]")
            this.text = this.el.querySelector("[data-new-posts-text]")
            this.handleEvent("feed:new", () => {
              if (window.scrollY < 240) return
              this.count += 1
              const b = this.button
              this.text.textContent = this.count === 1 ? b.dataset.one : b.dataset.other.replace("%{count}", this.count)
              this.js().show(b)
            })
            this.button.addEventListener("click", () => {
              this.count = 0
              this.js().hide(this.button)
              this.el.scrollIntoView({behavior: "smooth", block: "start"})
            })
          }
        }
      </script>
    </div>
    """
  end

  defp target_options(scope, targets, sections) do
    Enum.map(targets, fn
      nil -> {gettext_term(scope, :course, "The whole %{term}"), ""}
      id -> {Enum.find_value(sections, id, &(&1.id == id && &1.name)), id}
    end)
  end

  attr :post, :map, required: true
  attr :current_scope, :map, required: true
  attr :timezone, :string, required: true
  attr :can_moderate, :boolean, required: true
  attr :editing, :boolean, required: true
  attr :edit_form, :any, required: true
  attr :myself, :any, required: true

  defp post(assigns) do
    assigns =
      assign(assigns,
        mine: assigns.post.author_id == assigns.current_scope.user.id,
        author: assigns.post.author
      )

    ~H"""
    <article class="rounded-card border border-line bg-surface p-5 shadow-sm">
      <header class="mb-3 flex items-start gap-3">
        <.avatar
          :if={@author}
          name={User.display_name(@author)}
          src={Paths.avatar(@current_scope, @author)}
          size="md"
        />
        <div class="min-w-0 flex-1">
          <p class="font-semibold">
            {(@author && User.display_name(@author)) || gettext("Former member")}
          </p>
          <p class="flex flex-wrap items-center gap-x-2 text-sm text-ink-muted">
            <time datetime={DateTime.to_iso8601(@post.published_at)}>
              {Format.datetime(@post.published_at, @timezone, :short)}
            </time>
            <span :if={@post.edited_at}>· {gettext("edited")}</span>
            <.badge :if={@post.section} family="airampo">{@post.section.name}</.badge>
          </p>
        </div>
        <div :if={(@mine or @can_moderate) and not @editing} class="flex gap-1">
          <.icon_button
            :if={@mine}
            icon="pencil-simple"
            label={gettext("Edit")}
            size="sm"
            phx-click="edit"
            phx-value-id={@post.id}
            phx-target={@myself}
          />
          <.icon_button
            icon="trash"
            label={gettext("Delete")}
            size="sm"
            phx-click="delete"
            phx-value-id={@post.id}
            phx-target={@myself}
            data-confirm={gettext("Delete this post?")}
          />
        </div>
      </header>

      <.form
        :if={@editing}
        for={@edit_form}
        id={"edit-post-#{@post.id}"}
        phx-submit="save_edit"
        phx-target={@myself}
      >
        <.rich_text_editor
          id={"edit-editor-#{@post.id}"}
          field={@edit_form[:body]}
          label={gettext("Edit")}
        />
        <div class="flex gap-2">
          <.button phx-disable-with={gettext("Saving...")}>{gettext("Save")}</.button>
          <.button type="button" variant="ghost" phx-click="cancel_edit" phx-target={@myself}>
            {gettext("Cancel")}
          </.button>
        </div>
      </.form>

      <.rich_text :if={!@editing} id={"post-body-#{@post.id}"} doc={@post.body} />
    </article>
    """
  end
end
