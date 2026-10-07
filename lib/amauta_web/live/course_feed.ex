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

  alias Amauta.Feed.Actions.{
    DeletePost,
    DeleteReply,
    HideReply,
    MuteMember,
    PinPost,
    PublishPost,
    ReorderPinned,
    ReplyToPost,
    SaveDraft,
    SetRepliesEnabled,
    UpdatePost,
    UpdateReply
  }

  alias AmautaWeb.{Format, Paths}

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       editor_key: 0,
       editing: nil,
       edit_form: nil,
       loaded: false,
       replying: nil,
       reply_form: nil,
       reply_key: 0,
       editing_reply: nil,
       edit_reply_form: nil
     )}
  end

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
        can_reply: Feed.can_reply?(scope, course),
        muted: Feed.muted_ids(scope, course),
        timezone: scope.user.timezone || scope.institution.timezone
      )
      |> assign_new(:mentions, fn -> mention_candidates(scope, course) end)

    socket =
      if socket.assigns.loaded and not filter_changed,
        do: socket,
        else: load(socket)

    {:ok, socket}
  end

  # Personas que se pueden mencionar con «@» (RF-TAB-004): las del curso.
  defp mention_candidates(scope, course) do
    {teaching, students} = Amauta.Enrollments.participants(scope, course)

    for enrollment <- teaching ++ students,
        do: %{id: enrollment.user_id, label: User.display_name(enrollment.user)}
  end

  defp load(socket) do
    socket
    |> assign(loaded: true)
    |> load_posts()
    |> assign_composer()
  end

  # Fijadas arriba (RF-TAB-006) y el resto en el stream, sin repetirse.
  defp load_posts(socket) do
    %{current_scope: scope, course: course, section_filter: filter} = socket.assigns
    filters = %{"section" => filter}
    posts = Feed.list_posts(scope, course, filters)
    pinned = Feed.list_pinned(scope, course, filters)

    socket
    |> assign(pinned: pinned, empty: posts == [] and pinned == [])
    |> stream(:posts, posts, reset: true)
  end

  # Dibuja de nuevo una publicación donde esté: entre las fijadas o en el
  # stream.
  defp put_post(socket, post, opts \\ []) do
    if Enum.any?(socket.assigns.pinned, &(&1.id == post.id)) do
      update(socket, :pinned, fn pinned ->
        Enum.map(pinned, &if(&1.id == post.id, do: post, else: &1))
      end)
    else
      stream_insert(socket, :posts, post, opts)
    end
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
  defp apply_event(socket, :deleted, post) do
    socket
    |> stream_delete(:posts, post)
    |> update(:pinned, fn pinned -> Enum.reject(pinned, &(&1.id == post.id)) end)
  end

  # Cambió qué está fijado o su orden: se vuelven a armar las dos listas.
  defp apply_event(socket, :pinned, _post), do: load_posts(socket)

  defp apply_event(socket, event, post) do
    %{current_scope: scope, course: course, section_filter: filter} = socket.assigns

    case Feed.get_visible(scope, course, post.id) do
      nil ->
        socket

      visible ->
        if filter not in [nil, ""] and visible.section_id not in [nil, filter] do
          socket
        else
          # Lo nuevo va arriba; lo actualizado (edición, respuestas) queda en
          # su lugar.
          socket =
            if event == :published,
              do: put_post(socket, visible, at: 0),
              else: put_post(socket, visible)

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
         |> put_post(post)}
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
    {:noreply, if(post, do: put_post(socket, post), else: socket)}
  end

  def handle_event("save_edit", %{"edit" => %{"body" => body}}, socket) do
    params = %{"post_id" => socket.assigns.editing, "body" => body}

    case Actions.run(UpdatePost, socket.assigns.current_scope, params) do
      {:ok, post} ->
        {:noreply, socket |> assign(editing: nil, edit_form: nil) |> refresh_post(post.id)}

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

  ## Fijadas (RF-TAB-006)

  # Con un clic queda al final de las fijadas; arrastrada a la zona de
  # destacadas, llega con el orden nuevo (`ids`).
  def handle_event("pin", %{"id" => id} = params, socket) do
    with {:ok, _} <- pin(socket, id, true),
         {:ok, _} <- reorder_pins(socket, params["ids"]) do
      {:noreply, socket}
    else
      {:error, _} -> {:noreply, put_flash_message(socket, gettext("That could not be done."))}
    end
  end

  def handle_event("unpin", %{"id" => id}, socket) do
    case pin(socket, id, false) do
      {:ok, _} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash_message(socket, gettext("That could not be done."))}
    end
  end

  def handle_event("reorder_pins", %{"ids" => ids}, socket) do
    case reorder_pins(socket, ids) do
      {:ok, _} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash_message(socket, gettext("That could not be done."))}
    end
  end

  # Subir o bajar con los botones (teclado y pantallas táctiles).
  def handle_event("move_pin", %{"id" => id, "dir" => dir}, socket) do
    ids = Enum.map(socket.assigns.pinned, & &1.id)
    index = Enum.find_index(ids, &(&1 == id))
    target = if dir == "up", do: index - 1, else: index + 1

    if index && target in 0..(length(ids) - 1)//1 do
      ids = ids |> List.replace_at(index, Enum.at(ids, target)) |> List.replace_at(target, id)
      handle_event("reorder_pins", %{"ids" => ids}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("pin_expiry", %{"pin" => %{"post_id" => id, "expires_on" => date}}, socket) do
    params = %{
      "post_id" => id,
      "pinned" => true,
      "expires_at" => end_of_day(date, socket.assigns.timezone)
    }

    case Actions.run(PinPost, socket.assigns.current_scope, params) do
      {:ok, _} ->
        {:noreply, socket}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash_message(socket, gettext("Choose a date in the future."))}

      {:error, _} ->
        {:noreply, put_flash_message(socket, gettext("That could not be done."))}
    end
  end

  ## Respuestas (RF-TAB-004) y moderación (RF-TAB-007)

  def handle_event("reply", %{"post" => post_id} = params, socket) do
    target = {post_id, blank_to_nil(params["parent"])}

    {:noreply,
     socket
     |> assign(replying: target, reply_form: to_form(%{"body" => nil}, as: "reply"))
     |> update(:reply_key, &(&1 + 1))
     |> refresh_post(post_id)}
  end

  def handle_event("cancel_reply", _params, socket) do
    {post_id, _parent} = socket.assigns.replying
    {:noreply, socket |> assign(replying: nil, reply_form: nil) |> refresh_post(post_id)}
  end

  def handle_event("send_reply", %{"reply" => %{"body" => body}}, socket) do
    {post_id, parent_id} = socket.assigns.replying
    params = %{"post_id" => post_id, "parent_id" => parent_id, "body" => body}

    case Actions.run(ReplyToPost, socket.assigns.current_scope, params) do
      {:ok, _reply} ->
        {:noreply, socket |> assign(replying: nil, reply_form: nil) |> refresh_post(post_id)}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash_message(socket, gettext("Write something first."))}

      {:error, _} ->
        {:noreply, put_flash_message(socket, gettext("That could not be done."))}
    end
  end

  def handle_event("edit_reply", %{"id" => id, "post" => post_id}, socket) do
    case Feed.get_reply(socket.assigns.current_scope, id) do
      %{body: body} ->
        {:noreply,
         socket
         |> assign(
           editing_reply: id,
           edit_reply_form: to_form(%{"body" => body}, as: "edit_reply")
         )
         |> refresh_post(post_id)}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_edit_reply", %{"post" => post_id}, socket),
    do:
      {:noreply,
       socket |> assign(editing_reply: nil, edit_reply_form: nil) |> refresh_post(post_id)}

  def handle_event("save_reply", %{"edit_reply" => %{"body" => body}}, socket) do
    params = %{"reply_id" => socket.assigns.editing_reply, "body" => body}

    case Actions.run(UpdateReply, socket.assigns.current_scope, params) do
      {:ok, reply} ->
        {:noreply,
         socket
         |> assign(editing_reply: nil, edit_reply_form: nil)
         |> refresh_post(reply.post_id)}

      {:error, _} ->
        {:noreply, put_flash_message(socket, gettext("That could not be done."))}
    end
  end

  def handle_event("delete_reply", %{"id" => id}, socket),
    do: run_reply_action(socket, DeleteReply, %{"reply_id" => id})

  def handle_event("hide_reply", %{"id" => id, "hidden" => hidden}, socket),
    do: run_reply_action(socket, HideReply, %{"reply_id" => id, "hidden" => hidden})

  def handle_event("toggle_replies", %{"post" => id, "enabled" => enabled}, socket),
    do: run_reply_action(socket, SetRepliesEnabled, %{"post_id" => id, "enabled" => enabled})

  def handle_event("mute", %{"user" => user_id, "muted" => muted, "post" => post_id}, socket) do
    params = %{"course_id" => socket.assigns.course.id, "user_id" => user_id, "muted" => muted}

    case Actions.run(MuteMember, socket.assigns.current_scope, params) do
      {:ok, _} ->
        message =
          if muted == "true",
            do: gettext("Muted in this feed: they can read, but not post or reply."),
            else: gettext("They can post and reply again.")

        send(self(), {:put_flash, :info, message})

        {:noreply,
         socket
         |> assign(muted: Feed.muted_ids(socket.assigns.current_scope, socket.assigns.course))
         |> refresh_post(post_id)}

      {:error, _} ->
        {:noreply, put_flash_message(socket, gettext("That could not be done."))}
    end
  end

  defp pin(socket, id, pinned),
    do: Actions.run(PinPost, socket.assigns.current_scope, %{"post_id" => id, "pinned" => pinned})

  defp reorder_pins(_socket, nil), do: {:ok, nil}

  # La persona ve solo parte de las fijadas (por su comisión o el filtro):
  # el orden nuevo se aplica a esas, sin mover las que no ve.
  defp reorder_pins(socket, ids) do
    %{current_scope: scope, course: course} = socket.assigns
    full = Feed.pinned_ids(scope, course)
    ordered = ids |> Enum.uniq() |> Enum.filter(&(&1 in full))

    {order, _rest} =
      Enum.map_reduce(full, ordered, fn
        id, [next | rest] = all -> if id in ordered, do: {next, rest}, else: {id, all}
        id, [] -> {id, []}
      end)

    Actions.run(ReorderPinned, scope, %{"course_id" => course.id, "post_ids" => order})
  end

  # La fecha de vencimiento se toma hasta el final de ese día, en la zona
  # horaria de la persona.
  defp end_of_day(date, timezone) do
    with {:ok, date} <- Date.from_iso8601(date),
         {:ok, datetime} <- DateTime.new(date, ~T[23:59:59.999999], timezone) do
      DateTime.shift_zone!(datetime, "Etc/UTC")
    else
      _ -> nil
    end
  end

  # El cambio llega a todos por el tema del tablón; acá no hace falta más.
  defp run_reply_action(socket, action, params) do
    case Actions.run(action, socket.assigns.current_scope, params) do
      {:ok, _} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash_message(socket, gettext("That could not be done."))}
    end
  end

  # Vuelve a dibujar una publicación (cambió el estado de sus respuestas).
  defp refresh_post(socket, post_id) do
    case Feed.get_visible(socket.assigns.current_scope, socket.assigns.course, post_id) do
      nil -> socket
      post -> put_post(socket, post)
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

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
            mentions={@mentions}
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

        <section
          :if={@pinned != [] or @can_moderate}
          id="feed-pinned"
          phx-hook=".PinZone"
          phx-target={@myself}
          aria-label={gettext("Pinned posts")}
          class="mb-4 grid gap-4 rounded-card data-dragging:outline-2 data-dragging:outline-offset-4 data-dragging:outline-dashed data-dragging:outline-primary"
        >
          <p
            :if={@pinned == [] and @can_moderate}
            class="hidden min-h-24 items-center justify-center gap-2 text-sm text-ink-muted in-data-dragging:flex"
          >
            <.icon name="push-pin" class="size-5" /> {gettext("Drop a post here to pin it")}
          </p>
          <ol :if={@pinned != []} class="grid gap-4" aria-label={gettext("Pinned posts")}>
            <li
              :for={{post, index} <- Enum.with_index(@pinned)}
              id={"pinned-#{post.id}"}
              data-pinned-item
              data-post-id={post.id}
            >
              <.post
                post={post}
                ui={ui(assigns)}
                pin={%{first: index == 0, last: index == length(@pinned) - 1}}
              />
            </li>
          </ol>
        </section>

        <ol id="feed-posts" phx-update="stream" class="grid gap-4" aria-label={gettext("Feed")}>
          <li :for={{dom_id, post} <- @streams.posts} id={dom_id} data-post-id={post.id}>
            <.post post={post} ui={ui(assigns)} />
          </li>
        </ol>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".PinZone">
        // Zona de destacadas (RF-TAB-006): quien modera arrastra una
        // publicación desde su manija para fijarla o para cambiar el orden.
        // Los botones de cada fijada hacen lo mismo con teclado o táctil.
        export default {
          mounted() {
            this.onStart = (e) => {
              const handle = e.target.closest?.("[data-drag-handle]")
              const item = handle?.closest("[data-post-id]")
              if (!item) return
              this.dragId = item.dataset.postId
              e.dataTransfer.effectAllowed = "move"
              e.dataTransfer.setData("text/plain", this.dragId)
              e.dataTransfer.setDragImage(item, 24, 24)
              this.el.dataset.dragging = ""
            }
            this.onEnd = () => {
              delete this.el.dataset.dragging
              this.dragId = null
            }
            document.addEventListener("dragstart", this.onStart)
            document.addEventListener("dragend", this.onEnd)
            this.el.addEventListener("dragover", (e) => { if (this.dragId) e.preventDefault() })
            this.el.addEventListener("drop", (e) => {
              if (!this.dragId) return
              e.preventDefault()
              const id = this.dragId
              const items = [...this.el.querySelectorAll("[data-pinned-item]")]
              const ids = items.map((i) => i.dataset.postId).filter((x) => x !== id)
              const before = items.find((i) => {
                const r = i.getBoundingClientRect()
                return i.dataset.postId !== id && e.clientY < r.top + r.height / 2
              })
              ids.splice(before ? ids.indexOf(before.dataset.postId) : ids.length, 0, id)
              const pinned = items.some((i) => i.dataset.postId === id)
              this.pushEventTo(this.el, pinned ? "reorder_pins" : "pin", {id, ids})
              this.onEnd()
            })
          },
          destroyed() {
            document.removeEventListener("dragstart", this.onStart)
            document.removeEventListener("dragend", this.onEnd)
          }
        }
      </script>

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

  # Estado de la interacción que necesitan las publicaciones del stream.
  defp ui(assigns) do
    Map.take(assigns, [
      :current_scope,
      :timezone,
      :can_moderate,
      :can_reply,
      :muted,
      :editing,
      :edit_form,
      :replying,
      :reply_form,
      :reply_key,
      :editing_reply,
      :edit_reply_form,
      :mentions,
      :myself
    ])
  end

  attr :post, :map, required: true
  attr :ui, :map, required: true

  attr :pin, :map,
    default: nil,
    doc: "Entre las fijadas: `%{first: bool, last: bool}` para ordenarla."

  defp post(assigns) do
    %{post: post, ui: ui} = assigns
    user_id = ui.current_scope.user.id
    replies = Enum.group_by(post.replies, & &1.parent_id)

    assigns =
      assign(assigns,
        mine: post.author_id == user_id,
        author: post.author,
        editing: ui.editing == post.id,
        top_replies: Map.get(replies, nil, []),
        children: replies,
        replies_count: length(post.replies),
        can_toggle: post.author_id == user_id or ui.can_moderate,
        can_answer: ui.can_reply and post.replies_enabled
      )

    ~H"""
    <article class={[
      "rounded-card border bg-surface p-5 shadow-sm",
      if(@pin, do: "border-primary", else: "border-line")
    ]}>
      <header class="mb-3 flex items-start gap-3">
        <span
          :if={@ui.can_moderate and not @editing}
          data-drag-handle
          draggable="true"
          aria-hidden="true"
          title={gettext("Drag to the pinned area")}
          class="-ms-2 hidden cursor-grab self-center text-ink-muted hover:text-ink md:block"
        >
          <.icon name="dots-six-vertical" class="size-5" />
        </span>
        <.avatar
          :if={@author}
          name={User.display_name(@author)}
          src={Paths.avatar(@ui.current_scope, @author)}
          size="md"
        />
        <div class="min-w-0 flex-1">
          <p class="font-semibold">
            {(@author && User.display_name(@author)) || gettext("Former member")}
            <.badge :if={@author && MapSet.member?(@ui.muted, @author.id)} family="nogal" class="ms-1">
              {gettext("muted")}
            </.badge>
          </p>
          <p class="flex flex-wrap items-center gap-x-2 text-sm text-ink-muted">
            <time datetime={DateTime.to_iso8601(@post.published_at)}>
              {Format.datetime(@post.published_at, @ui.timezone, :short)}
            </time>
            <span :if={@post.edited_at}>· {gettext("edited")}</span>
            <.badge :if={@post.section} family="airampo">{@post.section.name}</.badge>
            <span :if={@pin} class="inline-flex items-center gap-1 font-semibold text-anil-deep">
              <.icon name="push-pin" class="size-3.5" /> {gettext("Pinned")}
              <span :if={@post.pin_expires_at} class="font-normal">
                {gettext("until %{date}", date: Format.date(@post.pin_expires_at, @ui.timezone))}
              </span>
            </span>
          </p>
        </div>
        <.dropdown
          :if={(@mine or @ui.can_moderate) and not @editing}
          id={"post-menu-#{@post.id}"}
          label={gettext("Post options")}
        >
          <:trigger><.icon name="dots-three" class="size-5 text-ink-muted" /></:trigger>
          <.dropdown_item
            :if={@mine}
            icon="pencil-simple"
            phx-click="edit"
            phx-value-id={@post.id}
            phx-target={@ui.myself}
          >
            {gettext("Edit")}
          </.dropdown_item>
          <.dropdown_item
            :if={@ui.can_moderate}
            icon={if @pin, do: "push-pin-slash", else: "push-pin"}
            phx-click={if @pin, do: "unpin", else: "pin"}
            phx-value-id={@post.id}
            phx-target={@ui.myself}
          >
            {if @pin, do: gettext("Unpin"), else: gettext("Pin to the top")}
          </.dropdown_item>
          <.mute_item :if={!@mine && @author} user={@author} post={@post} ui={@ui} />
          <.dropdown_item
            icon="trash"
            phx-click="delete"
            phx-value-id={@post.id}
            phx-target={@ui.myself}
            data-confirm={gettext("Delete this post?")}
          >
            {gettext("Delete")}
          </.dropdown_item>
        </.dropdown>
      </header>

      <.pin_controls :if={@pin && @ui.can_moderate && !@editing} post={@post} pin={@pin} ui={@ui} />

      <.form
        :if={@editing}
        for={@ui.edit_form}
        id={"edit-post-#{@post.id}"}
        phx-submit="save_edit"
        phx-target={@ui.myself}
      >
        <.rich_text_editor
          id={"edit-editor-#{@post.id}"}
          field={@ui.edit_form[:body]}
          label={gettext("Edit")}
          mentions={@ui.mentions}
        />
        <div class="flex gap-2">
          <.button phx-disable-with={gettext("Saving...")}>{gettext("Save")}</.button>
          <.button type="button" variant="ghost" phx-click="cancel_edit" phx-target={@ui.myself}>
            {gettext("Cancel")}
          </.button>
        </div>
      </.form>

      <.rich_text :if={!@editing} id={"post-body-#{@post.id}"} doc={@post.body} />

      <section
        id={"replies-#{@post.id}"}
        class="mt-4 border-t border-line pt-3"
        aria-label={gettext("Replies")}
      >
        <div class="flex flex-wrap items-center justify-between gap-2 text-sm text-ink-muted">
          <span>{ngettext("%{count} reply", "%{count} replies", @replies_count)}</span>
          <span :if={!@post.replies_enabled}>· {gettext("Replies are closed")}</span>
          <.button
            :if={@can_toggle}
            type="button"
            variant="ghost"
            size="sm"
            phx-click="toggle_replies"
            phx-value-post={@post.id}
            phx-value-enabled={to_string(!@post.replies_enabled)}
            phx-target={@ui.myself}
            class="ms-auto"
          >
            {if @post.replies_enabled, do: gettext("Close replies"), else: gettext("Open replies")}
          </.button>
        </div>

        <ul :if={@top_replies != []} class="mt-2 grid gap-3">
          <li :for={reply <- @top_replies} id={"reply-#{reply.id}"}>
            <.reply reply={reply} post={@post} ui={@ui} can_answer={@can_answer} />
            <ul
              :if={Map.has_key?(@children, reply.id)}
              class="mt-3 grid gap-3 border-s-2 border-line ps-4"
            >
              <li :for={child <- @children[reply.id]} id={"reply-#{child.id}"}>
                <.reply reply={child} post={@post} ui={@ui} can_answer={@can_answer} />
              </li>
            </ul>
            <.reply_form
              :if={@ui.replying == {@post.id, reply.id}}
              post={@post}
              ui={@ui}
            />
          </li>
        </ul>

        <.reply_form :if={@ui.replying == {@post.id, nil}} post={@post} ui={@ui} />

        <.button
          :if={@can_answer and @ui.replying == nil}
          type="button"
          variant="ghost"
          size="sm"
          icon="chats-circle"
          phx-click="reply"
          phx-value-post={@post.id}
          phx-target={@ui.myself}
          class="mt-2"
        >
          {gettext("Reply")}
        </.button>
      </section>
    </article>
    """
  end

  attr :post, :map, required: true
  attr :pin, :map, required: true
  attr :ui, :map, required: true

  # Para quien modera, en una fijada: vencimiento y orden (RF-TAB-006).
  defp pin_controls(assigns) do
    expires = assigns.post.pin_expires_at

    assigns =
      assign(assigns,
        expires_on:
          expires &&
            expires |> DateTime.shift_zone!(assigns.ui.timezone) |> DateTime.to_date()
      )

    ~H"""
    <div class="mb-3 flex flex-wrap items-center gap-2 text-sm text-ink-muted">
      <.form
        for={%{}}
        as={:pin}
        id={"pin-expiry-#{@post.id}"}
        phx-change="pin_expiry"
        phx-target={@ui.myself}
      >
        <.input type="hidden" name="pin[post_id]" value={@post.id} />
        <.input
          type="date"
          inline
          id={"pin-expires-#{@post.id}"}
          name="pin[expires_on]"
          value={@expires_on}
          label={gettext("Unpin on")}
        />
      </.form>
      <div class="ms-auto flex gap-1">
        <.icon_button
          :if={!@pin.first}
          icon="arrow-up"
          label={gettext("Move up")}
          size="sm"
          phx-click="move_pin"
          phx-value-id={@post.id}
          phx-value-dir="up"
          phx-target={@ui.myself}
        />
        <.icon_button
          :if={!@pin.last}
          icon="arrow-down"
          label={gettext("Move down")}
          size="sm"
          phx-click="move_pin"
          phx-value-id={@post.id}
          phx-value-dir="down"
          phx-target={@ui.myself}
        />
      </div>
    </div>
    """
  end

  attr :user, :map, required: true
  attr :post, :map, required: true
  attr :ui, :map, required: true

  # Silenciar desde el menú de una publicación (RF-TAB-007).
  defp mute_item(assigns) do
    assigns = assign(assigns, muted: MapSet.member?(assigns.ui.muted, assigns.user.id))

    ~H"""
    <.dropdown_item
      :if={@ui.can_moderate}
      icon={if @muted, do: "user", else: "lock"}
      phx-click="mute"
      phx-value-user={@user.id}
      phx-value-muted={to_string(!@muted)}
      phx-value-post={@post.id}
      phx-target={@ui.myself}
      data-confirm={
        !@muted &&
          gettext("Mute %{name}? They will be able to read, but not post or reply here.",
            name: User.display_name(@user)
          )
      }
    >
      {if @muted,
        do: gettext("Let %{name} post again", name: User.display_name(@user)),
        else: gettext("Mute %{name} in this feed", name: User.display_name(@user))}
    </.dropdown_item>
    """
  end

  attr :reply, :map, required: true
  attr :post, :map, required: true
  attr :ui, :map, required: true
  attr :can_answer, :boolean, required: true

  defp reply(assigns) do
    %{reply: reply, ui: ui} = assigns
    mine = reply.author_id == ui.current_scope.user.id

    assigns =
      assign(assigns,
        mine: mine,
        author: reply.author,
        editing: ui.editing_reply == reply.id,
        hidden: not is_nil(reply.hidden_at),
        # El contenido oculto lo ven su autor y quien modera.
        show_body: is_nil(reply.hidden_at) or mine or ui.can_moderate
      )

    ~H"""
    <div class="flex items-start gap-3">
      <.avatar
        :if={@author}
        name={User.display_name(@author)}
        src={Paths.avatar(@ui.current_scope, @author)}
        size="sm"
      />
      <div class="min-w-0 flex-1">
        <p class="flex flex-wrap items-center gap-x-2 text-sm">
          <span class="font-semibold">
            {(@author && User.display_name(@author)) || gettext("Former member")}
          </span>
          <time class="text-ink-muted" datetime={DateTime.to_iso8601(@reply.inserted_at)}>
            {Format.datetime(@reply.inserted_at, @ui.timezone, :short)}
          </time>
          <span :if={@reply.edited_at} class="text-ink-muted">· {gettext("edited")}</span>
          <.badge :if={@hidden} family="nogal">{gettext("hidden")}</.badge>
        </p>

        <p :if={!@show_body} class="text-sm italic text-ink-muted">
          {gettext("This reply was hidden by the teaching team.")}
        </p>

        <.form
          :if={@editing}
          for={@ui.edit_reply_form}
          id={"edit-reply-#{@reply.id}"}
          phx-submit="save_reply"
          phx-target={@ui.myself}
        >
          <.rich_text_editor
            id={"edit-reply-editor-#{@reply.id}"}
            field={@ui.edit_reply_form[:body]}
            label={gettext("Edit reply")}
            mentions={@ui.mentions}
          />
          <div class="flex gap-2">
            <.button size="sm" phx-disable-with={gettext("Saving...")}>{gettext("Save")}</.button>
            <.button
              type="button"
              size="sm"
              variant="ghost"
              phx-click="cancel_edit_reply"
              phx-value-post={@post.id}
              phx-target={@ui.myself}
            >
              {gettext("Cancel")}
            </.button>
          </div>
        </.form>

        <.rich_text
          :if={@show_body and not @editing}
          id={"reply-body-#{@reply.id}"}
          doc={@reply.body}
          class="text-sm"
        />

        <div :if={not @editing} class="mt-1 flex flex-wrap gap-1">
          <.button
            :if={@can_answer and @ui.replying == nil}
            type="button"
            variant="ghost"
            size="sm"
            phx-click="reply"
            phx-value-post={@post.id}
            phx-value-parent={@reply.id}
            phx-target={@ui.myself}
          >
            {gettext("Reply")}
          </.button>
          <.icon_button
            :if={@mine}
            icon="pencil-simple"
            label={gettext("Edit reply")}
            size="sm"
            phx-click="edit_reply"
            phx-value-id={@reply.id}
            phx-value-post={@post.id}
            phx-target={@ui.myself}
          />
          <.icon_button
            :if={@ui.can_moderate}
            icon={if @hidden, do: "eye", else: "eye-slash"}
            label={if @hidden, do: gettext("Show reply"), else: gettext("Hide reply")}
            size="sm"
            phx-click="hide_reply"
            phx-value-id={@reply.id}
            phx-value-hidden={to_string(!@hidden)}
            phx-target={@ui.myself}
          />
          <.icon_button
            :if={@mine or @ui.can_moderate}
            icon="trash"
            label={gettext("Delete reply")}
            size="sm"
            phx-click="delete_reply"
            phx-value-id={@reply.id}
            phx-target={@ui.myself}
            data-confirm={gettext("Delete this reply?")}
          />
          <.mute_button :if={!@mine && @author} user={@author} post={@post} ui={@ui} />
        </div>
      </div>
    </div>
    """
  end

  attr :post, :map, required: true
  attr :ui, :map, required: true

  defp reply_form(assigns) do
    ~H"""
    <.form
      for={@ui.reply_form}
      id={"reply-form-#{@post.id}"}
      phx-submit="send_reply"
      phx-target={@ui.myself}
      class="mt-3"
    >
      <.rich_text_editor
        id={"reply-editor-#{@post.id}-#{@ui.reply_key}"}
        field={@ui.reply_form[:body]}
        label={gettext("Your reply")}
        placeholder={gettext("Write a reply. Use «@» to mention someone.")}
        mentions={@ui.mentions}
      />
      <div class="flex gap-2">
        <.button size="sm" icon="paper-plane-tilt" phx-disable-with={gettext("Sending...")}>
          {gettext("Reply")}
        </.button>
        <.button
          type="button"
          size="sm"
          variant="ghost"
          phx-click="cancel_reply"
          phx-target={@ui.myself}
        >
          {gettext("Cancel")}
        </.button>
      </div>
    </.form>
    """
  end

  attr :user, :map, required: true
  attr :post, :map, required: true
  attr :ui, :map, required: true

  # Silenciar a alguien en el tablón (RF-TAB-007), para quien modera.
  defp mute_button(assigns) do
    assigns = assign(assigns, muted: MapSet.member?(assigns.ui.muted, assigns.user.id))

    ~H"""
    <.icon_button
      :if={@ui.can_moderate}
      icon={if @muted, do: "user", else: "lock"}
      label={
        if @muted,
          do: gettext("Let %{name} post again", name: User.display_name(@user)),
          else: gettext("Mute %{name} in this feed", name: User.display_name(@user))
      }
      size="sm"
      phx-click="mute"
      phx-value-user={@user.id}
      phx-value-muted={to_string(!@muted)}
      phx-value-post={@post.id}
      phx-target={@ui.myself}
      data-confirm={
        !@muted &&
          gettext("Mute %{name}? They will be able to read, but not post or reply here.",
            name: User.display_name(@user)
          )
      }
    />
    """
  end
end
