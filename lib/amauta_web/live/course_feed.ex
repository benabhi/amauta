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
    PublishPost,
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
          # Lo nuevo va arriba; lo actualizado (edición, respuestas) queda en
          # su lugar.
          socket =
            if event == :published,
              do: stream_insert(socket, :posts, visible, at: 0),
              else: stream_insert(socket, :posts, visible)

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
      post -> stream_insert(socket, :posts, post)
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

        <ol id="feed-posts" phx-update="stream" class="grid gap-4" aria-label={gettext("Feed")}>
          <li :for={{dom_id, post} <- @streams.posts} id={dom_id}>
            <.post post={post} ui={ui(assigns)} />
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
    <article class="rounded-card border border-line bg-surface p-5 shadow-sm">
      <header class="mb-3 flex items-start gap-3">
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
          </p>
        </div>
        <div :if={(@mine or @ui.can_moderate) and not @editing} class="flex gap-1">
          <.icon_button
            :if={@mine}
            icon="pencil-simple"
            label={gettext("Edit")}
            size="sm"
            phx-click="edit"
            phx-value-id={@post.id}
            phx-target={@ui.myself}
          />
          <.icon_button
            icon="trash"
            label={gettext("Delete")}
            size="sm"
            phx-click="delete"
            phx-value-id={@post.id}
            phx-target={@ui.myself}
            data-confirm={gettext("Delete this post?")}
          />
          <.mute_button :if={!@mine && @author} user={@author} post={@post} ui={@ui} />
        </div>
      </header>

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
