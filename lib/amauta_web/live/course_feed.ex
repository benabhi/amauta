defmodule AmautaWeb.CourseFeed do
  @moduledoc """
  Tablón del curso (RF-TAB-001 a 003, 007 y 008), dentro de la pestaña
  Tablón de `AmautaWeb.CourseLive`.

  Tiene dos modos. En el tablón, cada publicación es una tarjeta compacta
  (el comienzo del texto, los adjuntos y cómo va la conversación) y las
  fijadas, una línea arriba. Con `post_id`, muestra esa publicación
  completa, con toda su conversación (su página).

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

  # De a cuántas respuestas más trae «Ver anteriores».
  @more 20

  # Cuántas respuestas más se muestran de entrada en la página de una
  # publicación (además de las del tablón).
  @single_window 30

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
       edit_reply_form: nil,
       # El editor para publicar arranca plegado en una línea.
       composer_open: false,
       has_draft: false,
       # Fijada cuyo vencimiento se está eligiendo (desde su menú).
       pin_editing: nil,
       # La publicación de su página (`post_id`), con toda su conversación.
       post_id: nil,
       single: nil,
       news: [],
       has_posts: false,
       # Cuántas respuestas mostrar, por publicación o respuesta, cuando
       # alguien pidió ver más (`Amauta.Feed.with_replies/3`).
       windows: %{},
       cursor: nil,
       more_posts: false,
       # Adjuntos de cada formulario abierto (RF-TAB-005), antes de guardar.
       files: %{composer: [], reply: [], edit_post: [], edit_reply: []}
     )}
  end

  @impl true
  def update(%{feed_event: {event, post}}, socket), do: {:ok, apply_event(socket, event, post)}

  # Un archivo terminó de subir en uno de los formularios.
  def update(%{uploaded: {upload_id, file}}, socket) do
    case upload_context(upload_id) do
      nil ->
        {:ok, socket}

      context ->
        files = Enum.take(socket.assigns.files[context] ++ [file], Feed.max_attachments())
        socket = put_files(socket, context, files)
        {:ok, if(context == :composer, do: save_draft(socket), else: socket)}
    end
  end

  def update(assigns, socket) do
    %{current_scope: scope, course: course} = assigns

    filter_changed =
      assigns.section_filter != socket.assigns[:section_filter] or
        assigns[:post_id] != socket.assigns[:post_id]

    socket =
      socket
      |> assign(assigns)
      |> assign(
        can_post: Feed.can_post?(scope, course),
        can_moderate: Feed.can_moderate?(scope, course),
        can_reply: Feed.can_reply?(scope, course),
        can_attach: Feed.can_attach?(scope, course),
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

  # Una sola publicación (su página): con toda su conversación.
  defp load_posts(%{assigns: %{post_id: id}} = socket) when is_binary(id) do
    # En su página la conversación es lo principal: se muestran más respuestas.
    socket =
      if Map.has_key?(socket.assigns.windows, id),
        do: socket,
        else: widen(socket, nil, id, @single_window)

    socket
    |> assign(single: visible(socket, id), pinned: [], news: [], empty: false, more_posts: false)
    |> stream(:posts, [], reset: true)
  end

  # Arriba, las novedades del curso: las fijadas (RF-TAB-006) y el contenido
  # que se empezó a ver. Abajo, la conversación (solo publicaciones), en el
  # stream, sin repetirse.
  defp load_posts(socket) do
    %{current_scope: scope, course: course, section_filter: filter} = socket.assigns
    windows = socket.assigns.windows

    posts =
      Feed.list_posts(scope, course, %{"section" => filter, "kind" => "post"}, windows: windows)

    socket
    |> assign(has_posts: posts != [])
    |> load_news()
    |> assign_page(posts)
    |> stream(:posts, posts, reset: true)
  end

  defp load_news(socket) do
    %{current_scope: scope, course: course, section_filter: filter} = socket.assigns

    pinned =
      Feed.list_pinned(scope, course, %{"section" => filter}, windows: socket.assigns.windows)

    news = Feed.list_news(scope, course)

    assign(socket,
      pinned: pinned,
      news: news,
      empty: not socket.assigns.has_posts and pinned == [] and news == []
    )
  end

  # Dónde sigue el tablón: la última publicación traída, y si puede haber más.
  defp assign_page(socket, posts) do
    assign(socket,
      cursor: List.last(posts) || socket.assigns.cursor,
      more_posts: length(posts) == Feed.page_size()
    )
  end

  # Publicación visible con las respuestas que se están mostrando.
  defp visible(socket, id) do
    %{current_scope: scope, course: course, windows: windows} = socket.assigns
    Feed.get_visible(scope, course, id, windows: windows)
  end

  # Dibuja de nuevo una publicación donde esté: la de su página, entre las
  # fijadas o en el stream.
  defp put_post(socket, post, opts \\ [])

  defp put_post(%{assigns: %{post_id: id}} = socket, post, _opts) when is_binary(id),
    do: if(post.id == id, do: assign(socket, single: post), else: socket)

  defp put_post(socket, post, opts) do
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

  # En la página de una publicación no se publica.
  defp assign_composer(%{assigns: %{post_id: id}} = socket) when is_binary(id),
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

    files = if draft, do: Feed.attached_files(scope, draft), else: []

    socket
    |> assign(
      targets: targets,
      has_draft: draft != nil and draft_content?(draft.body, files),
      form: to_form(%{"body" => draft && draft.body, "section_id" => section}, as: "post")
    )
    |> put_files(:composer, files)
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
  # puede ver (y si coincide con el filtro de comisión). En la página de una
  # publicación solo importa esa (si la borran, la vista del curso vuelve al
  # tablón).
  defp apply_event(%{assigns: %{post_id: id}} = socket, event, post) when is_binary(id) do
    if post.id == id and event != :deleted, do: refresh_post(socket, id), else: socket
  end

  # Cambió qué está fijado o su orden: se vuelven a armar las dos listas.
  defp apply_event(socket, :pinned, _post), do: load_posts(socket)

  # Las tarjetas del contenido viven en las novedades, no en la conversación.
  defp apply_event(socket, _event, %{kind: "content"}), do: load_news(socket)

  defp apply_event(socket, :deleted, post) do
    socket
    |> stream_delete(:posts, post)
    |> update(:pinned, fn pinned -> Enum.reject(pinned, &(&1.id == post.id)) end)
  end

  defp apply_event(socket, event, post) do
    %{current_scope: scope, section_filter: filter} = socket.assigns

    case visible(socket, post.id) do
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

          socket = assign(socket, empty: false, has_posts: true)

          if event == :published and visible.author_id != scope.user.id,
            do: push_event(socket, "feed:new", %{}),
            else: socket
        end
    end
  end

  @impl true
  def handle_event("draft", %{"post" => params}, socket) do
    {:noreply, socket |> assign(form: to_form(params, as: "post")) |> save_draft()}
  end

  def handle_event("open_composer", _params, socket),
    do: {:noreply, assign(socket, composer_open: true)}

  # Cerrar no borra: lo escrito queda como borrador.
  def handle_event("close_composer", _params, socket),
    do: {:noreply, assign(socket, composer_open: false)}

  def handle_event("publish", %{"post" => params}, socket) do
    params =
      Map.merge(params, %{
        "course_id" => socket.assigns.course.id,
        "attachment_ids" => file_ids(socket, :composer)
      })

    case Actions.run(PublishPost, socket.assigns.current_scope, params) do
      {:ok, _post} ->
        # La publicación llega por el tema del tablón; acá se vacía el editor.
        {:noreply,
         socket
         |> update(:editor_key, &(&1 + 1))
         |> assign(composer_open: false, has_draft: false)
         |> put_files(:composer, [])
         |> assign(form: to_form(%{"section_id" => params["section_id"]}, as: "post"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        message = changeset.errors |> Keyword.values() |> List.first() |> translate_error()
        {:noreply, put_flash_message(socket, message)}

      {:error, _} ->
        {:noreply, put_flash_message(socket, gettext("That could not be done."))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case visible(socket, id) do
      nil ->
        {:noreply, socket}

      post ->
        {:noreply,
         socket
         |> assign(editing: post.id, edit_form: to_form(%{"body" => post.body}, as: "edit"))
         |> put_files(:edit_post, Enum.map(post.attachments, & &1.file))
         |> put_post(post)}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    post = visible(socket, socket.assigns.editing)

    socket = assign(socket, editing: nil, edit_form: nil)
    {:noreply, if(post, do: put_post(socket, post), else: socket)}
  end

  def handle_event("save_edit", %{"edit" => %{"body" => body}}, socket) do
    params = %{
      "post_id" => socket.assigns.editing,
      "body" => body,
      "attachment_ids" => file_ids(socket, :edit_post)
    }

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

  ## Hilos y publicaciones largos

  # «Ver anteriores»: de a `@more` respuestas más, de primer nivel o
  # anidadas (`parent`).
  def handle_event("more_replies", %{"post" => post_id} = params, socket) do
    parent = blank_to_nil(params["parent"])
    {:noreply, socket |> widen(parent, post_id, @more) |> refresh_post(post_id)}
  end

  # Publicaciones anteriores, al llegar al final del tablón (o con el botón).
  def handle_event("more_posts", _params, %{assigns: %{more_posts: false}} = socket),
    do: {:noreply, socket}

  def handle_event("more_posts", _params, socket) do
    %{current_scope: scope, course: course, section_filter: filter} = socket.assigns

    posts =
      Feed.list_posts(scope, course, %{"section" => filter, "kind" => "post"},
        before: socket.assigns.cursor,
        windows: socket.assigns.windows
      )

    {:noreply, socket |> assign_page(posts) |> stream(:posts, posts)}
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

  def handle_event("edit_pin_expiry", %{"id" => id}, socket),
    do: {:noreply, assign(socket, pin_editing: id)}

  def handle_event("close_pin_expiry", _params, socket),
    do: {:noreply, assign(socket, pin_editing: nil)}

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

  ## Adjuntos (RF-TAB-005)

  # Quitar un archivo de un formulario. En el borrador se guarda enseguida
  # (y el archivo se descarta); en los demás, al enviar.
  def handle_event("remove_file:" <> context, %{"id" => id}, socket) do
    context = String.to_existing_atom(context)
    files = Enum.reject(socket.assigns.files[context], &(&1.id == id))
    socket = put_files(socket, context, files)
    {:noreply, if(context == :composer, do: save_draft(socket), else: socket)}
  end

  ## Respuestas (RF-TAB-004) y moderación (RF-TAB-007)

  def handle_event("reply", %{"post" => post_id} = params, socket) do
    target = {post_id, blank_to_nil(params["parent"])}

    {:noreply,
     socket
     |> assign(replying: target, reply_form: to_form(%{"body" => nil}, as: "reply"))
     |> put_files(:reply, [])
     |> update(:reply_key, &(&1 + 1))
     |> refresh_post(post_id)}
  end

  def handle_event("cancel_reply", _params, socket) do
    {post_id, _parent} = socket.assigns.replying
    {:noreply, socket |> assign(replying: nil, reply_form: nil) |> refresh_post(post_id)}
  end

  def handle_event("send_reply", %{"reply" => %{"body" => body}}, socket) do
    {post_id, parent_id} = socket.assigns.replying

    params = %{
      "post_id" => post_id,
      "parent_id" => parent_id,
      "body" => body,
      "attachment_ids" => file_ids(socket, :reply)
    }

    case Actions.run(ReplyToPost, socket.assigns.current_scope, params) do
      {:ok, reply} ->
        # La propia se suma a lo que se ve, sin desplazar otra respuesta.
        {:noreply,
         socket
         |> assign(replying: nil, reply_form: nil)
         |> widen(reply.parent_id, post_id, 1)
         |> refresh_post(post_id)}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash_message(socket, gettext("Write something first."))}

      {:error, _} ->
        {:noreply, put_flash_message(socket, gettext("That could not be done."))}
    end
  end

  def handle_event("edit_reply", %{"id" => id, "post" => post_id}, socket) do
    case Feed.get_reply(socket.assigns.current_scope, id) do
      %{body: body} = reply ->
        {:noreply,
         socket
         |> assign(
           editing_reply: id,
           edit_reply_form: to_form(%{"body" => body}, as: "edit_reply")
         )
         |> put_files(:edit_reply, Feed.attached_files(socket.assigns.current_scope, reply))
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
    params = %{
      "reply_id" => socket.assigns.editing_reply,
      "body" => body,
      "attachment_ids" => file_ids(socket, :edit_reply)
    }

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

  # A qué formulario va cada zona de subida.
  defp upload_context("feed-upload-composer"), do: :composer
  defp upload_context("feed-upload-reply"), do: :reply
  defp upload_context("feed-upload-edit-post"), do: :edit_post
  defp upload_context("feed-upload-edit-reply"), do: :edit_reply
  defp upload_context(_id), do: nil

  defp put_files(socket, context, files),
    do: update(socket, :files, &Map.put(&1, context, files))

  defp file_ids(socket, context), do: Enum.map(socket.assigns.files[context], & &1.id)

  # Guarda el borrador con lo que hay en el editor y sus adjuntos.
  defp save_draft(%{assigns: %{form: nil}} = socket), do: socket

  defp save_draft(socket) do
    params =
      socket.assigns.form.params
      |> Map.take(["body", "section_id"])
      |> Map.merge(%{
        "course_id" => socket.assigns.course.id,
        "attachment_ids" => file_ids(socket, :composer)
      })

    Actions.run(SaveDraft, socket.assigns.current_scope, params)
    assign(socket, has_draft: draft_content?(params["body"], socket.assigns.files.composer))
  end

  # Si el borrador tiene algo: texto o adjuntos. Un borrador vacío (se abrió
  # el editor y no se escribió nada) no cuenta.
  defp draft_content?(_body, [_ | _]), do: true

  defp draft_content?(body, []) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, doc} -> draft_content?(doc, [])
      {:error, _} -> String.trim(body) != ""
    end
  end

  defp draft_content?(doc, []), do: not Amauta.RichText.blank?(doc)

  # Agranda la ventana de respuestas: las anidadas de `parent` o, sin él,
  # las de primer nivel de la publicación.
  defp widen(socket, parent, post_id, count) do
    {key, default} =
      if parent, do: {parent, Feed.child_window()}, else: {post_id, Feed.reply_window()}

    update(socket, :windows, &Map.update(&1, key, default + count, fn n -> n + count end))
  end

  # Vuelve a dibujar una publicación (cambió el estado de sus respuestas).
  defp refresh_post(socket, post_id) do
    case visible(socket, post_id) do
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
      <%!-- Plegado, el editor es una línea: lo primero son las publicaciones. --%>
      <button
        :if={@form && !@composer_open}
        id="feed-composer-open"
        type="button"
        phx-click="open_composer"
        phx-target={@myself}
        class="group flex min-h-14 w-full items-center gap-3 rounded-full border border-dashed border-line bg-surface-sunken ps-2 pe-2 text-start text-ink-muted transition-colors duration-fast hover:border-primary hover:text-ink focus-visible:outline-2 focus-visible:outline-primary"
      >
        <.avatar
          name={User.display_name(@current_scope.user)}
          src={Paths.avatar(@current_scope, @current_scope.user)}
          size="sm"
        />
        <span class="min-w-0 flex-1 truncate">
          {if @has_draft,
            do: gettext("Continue your draft…"),
            else: gettext_term(@current_scope, :course, "Share something with the %{term}…")}
        </span>
        <span class="inline-flex min-h-10 shrink-0 items-center gap-2 rounded-full bg-primary px-4 text-sm font-semibold text-on-primary transition-opacity duration-fast group-hover:opacity-90">
          <.icon name="pencil-simple" class="size-4" />
          <span class="hidden sm:inline">{gettext("New post")}</span>
        </span>
      </button>

      <.card :if={@form && @composer_open} id="feed-composer-card">
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
          <.attach_field context={:composer} ui={ui(assigns)} />
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div :if={length(@targets) > 1} class="w-60">
              <.input
                field={@form[:section_id]}
                type="select"
                aria-label={gettext("Audience")}
                options={target_options(@current_scope, @targets, @sections)}
              />
            </div>
            <div class="ms-auto flex gap-2">
              <.button
                type="button"
                variant="ghost"
                phx-click="close_composer"
                phx-target={@myself}
                title={gettext("The draft is kept.")}
              >
                {gettext("Close")}
              </.button>
              <.button icon="paper-plane-tilt" phx-disable-with={gettext("Publishing...")}>
                {gettext("Publish")}
              </.button>
            </div>
          </div>
        </.form>
      </.card>

      <div :if={@single} id="feed-post-page" class="grid gap-4">
        <.link
          navigate={Paths.course(@current_scope, @course)}
          class="inline-flex min-h-11 items-center gap-2 justify-self-start text-sm font-semibold text-ink-muted hover:text-ink"
        >
          <.icon name="arrow-left" class="size-4" /> {gettext("Back to the feed")}
        </.link>
        <.post post={@single} ui={ui(assigns)} pin={single_pin(@single)} />
      </div>

      <div :if={!@post_id} id={"#{@id}-new"} phx-hook=".FeedNewPosts" class="relative">
        <button
          type="button"
          data-new-posts
          data-one={gettext("1 new post")}
          data-other={gettext("%{count} new posts", count: "%{count}")}
          class="sticky top-16 z-30 mx-auto mb-2 hidden min-h-11 items-center gap-2 rounded-full bg-primary px-4 text-sm font-semibold text-on-primary shadow-md"
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

        <%!-- Novedades del curso: lo fijado y el contenido nuevo, aparte de la
             conversación. También es la zona donde se suelta para fijar. --%>
        <section
          :if={@pinned != [] or @news != [] or @can_moderate}
          id="feed-pinned"
          phx-hook=".PinZone"
          phx-target={@myself}
          aria-labelledby="feed-news-title"
          class={[
            "mb-6 rounded-card data-dragging:outline-2 data-dragging:outline-offset-4 data-dragging:outline-dashed data-dragging:outline-primary",
            (@pinned != [] or @news != []) && "border border-line bg-surface shadow-sm"
          ]}
        >
          <header
            :if={@pinned != [] or @news != []}
            class="flex items-center gap-2 border-b border-line px-4 py-2.5"
          >
            <.icon name="star" class="size-4 text-anil-deep" />
            <h2 id="feed-news-title" class="text-sm font-semibold">
              {gettext_term(@current_scope, :course, "What's new in the %{term}")}
            </h2>
            <.link
              navigate={Paths.course(@current_scope, @course, :content)}
              class="ms-auto inline-flex min-h-9 items-center gap-1 text-sm font-semibold text-anil-deep hover:underline"
            >
              {gettext("All content")} <.icon name="arrow-right" class="size-4" />
            </.link>
          </header>
          <p
            :if={@pinned == [] and @news == [] and @can_moderate}
            class="hidden min-h-24 items-center justify-center gap-2 text-sm text-ink-muted in-data-dragging:flex"
          >
            <.icon name="push-pin" class="size-5" /> {gettext("Drop a post here to pin it")}
          </p>
          <ol :if={@pinned != [] or @news != []} aria-label={gettext("What's new")}>
            <li
              :for={{post, index} <- Enum.with_index(@pinned)}
              id={"pinned-#{post.id}"}
              data-pinned-item
              data-post-id={post.id}
              class="border-t border-line first:border-t-0"
            >
              <.pinned_row
                post={post}
                ui={ui(assigns)}
                pin={%{first: index == 0, last: index == length(@pinned) - 1}}
              />
            </li>
            <li
              :for={post <- @news}
              id={"news-#{post.id}"}
              data-post-id={post.id}
              class="border-t border-line first:border-t-0"
            >
              <.news_row post={post} ui={ui(assigns)} />
            </li>
          </ol>
        </section>

        <h2 :if={@has_posts} class="mb-3 text-sm font-semibold text-ink-muted">
          {gettext("Conversation")}
        </h2>

        <ol
          id="feed-posts"
          phx-update="stream"
          phx-viewport-bottom={@more_posts && "more_posts"}
          phx-target={@myself}
          class="grid gap-4"
          aria-label={gettext("Feed")}
        >
          <li :for={{dom_id, post} <- @streams.posts} id={dom_id} data-post-id={post.id}>
            <.post_card post={post} ui={ui(assigns)} />
          </li>
        </ol>

        <div :if={@more_posts} class="mt-4 flex justify-center">
          <.button
            id="feed-more-posts"
            type="button"
            variant="ghost"
            phx-click="more_posts"
            phx-target={@myself}
            phx-disable-with={gettext("Loading...")}
          >
            {gettext("View earlier posts")}
          </.button>
        </div>
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
              this.js().show(b, {display: "flex"})
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

  # En su página, una fijada vigente se muestra como tal (sin orden: eso se
  # cambia desde el tablón).
  defp single_pin(%{pinned_at: nil}), do: nil

  defp single_pin(post) do
    if is_nil(post.pin_expires_at) or DateTime.after?(post.pin_expires_at, DateTime.utc_now()),
      do: %{first: true, last: true}
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
      :pin_editing,
      :post_id,
      :mentions,
      :files,
      :can_attach,
      :course,
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

    assigns =
      assign(assigns,
        author: post.author,
        editing: ui.editing == post.id,
        hidden: post.top_reply_count - length(post.replies),
        can_answer: ui.can_reply and post.replies_enabled
      )

    ~H"""
    <article class={[
      "overflow-hidden rounded-card border bg-surface shadow-sm",
      if(@pin, do: "border-primary", else: "border-line")
    ]}>
      <div class="p-5">
        <header class="mb-3 flex items-center gap-3">
          <.avatar
            :if={@author}
            name={User.display_name(@author)}
            src={Paths.avatar(@ui.current_scope, @author)}
            size="md"
          />
          <div class="min-w-0 flex-1">
            <p class="font-semibold">
              {(@author && User.display_name(@author)) || gettext("Former member")}
              <.badge
                :if={@author && MapSet.member?(@ui.muted, @author.id)}
                family="nogal"
                class="ms-1"
              >
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
          <.badge :if={@pin} family="anil" icon="push-pin" class="shrink-0">
            {gettext("Pinned")}
            <span :if={@post.pin_expires_at} class="font-normal">
              {gettext("until %{date}", date: Format.date(@post.pin_expires_at, @ui.timezone))}
            </span>
          </.badge>
          <.post_menu :if={not @editing} post={@post} ui={@ui} pin={@pin} />
        </header>

        <.pin_expiry
          :if={@pin && @ui.can_moderate && !@editing && @ui.pin_editing == @post.id}
          post={@post}
          ui={@ui}
        />

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
          <.attach_field context={:edit_post} ui={@ui} />
          <div class="flex gap-2">
            <.button phx-disable-with={gettext("Saving...")}>{gettext("Save")}</.button>
            <.button type="button" variant="ghost" phx-click="cancel_edit" phx-target={@ui.myself}>
              {gettext("Cancel")}
            </.button>
          </div>
        </.form>

        <.collapsible :if={!@editing} id={"post-text-#{@post.id}"}>
          <.rich_text id={"post-body-#{@post.id}"} doc={@post.body} />
        </.collapsible>

        <.attachment_list
          :if={!@editing}
          id={"post-files-#{@post.id}"}
          files={Enum.map(@post.attachments, & &1.file)}
          tenant={@ui.current_scope}
          class="mt-3"
        />

        <p
          :if={@post.reply_count > 0 or !@post.replies_enabled}
          id={"reply-summary-#{@post.id}"}
          class="mt-4 flex flex-wrap items-center gap-x-4 text-sm text-ink-muted"
        >
          <span :if={@post.reply_count > 0} class="inline-flex items-center gap-1">
            <.icon name="chats-circle" class="size-4" />
            {ngettext("%{count} reply", "%{count} replies", @post.reply_count)}
          </span>
          <span :if={!@post.replies_enabled} class="inline-flex items-center gap-1">
            <.icon name="lock" class="size-4" /> {gettext("Replies are closed")}
          </span>
        </p>
      </div>

      <%!-- Las respuestas, en una franja aparte debajo de la publicación. --%>
      <section
        :if={@post.reply_count > 0 or @can_answer}
        id={"replies-#{@post.id}"}
        class="grid gap-3 border-t border-line bg-surface-sunken px-5 py-4"
        aria-label={gettext("Replies")}
      >
        <.more_replies count={@hidden} post={@post} ui={@ui} />

        <ul :if={@post.replies != []} class="grid gap-3">
          <li :for={reply <- @post.replies} id={"reply-#{reply.id}"}>
            <.reply reply={reply} post={@post} ui={@ui} can_answer={@can_answer} />
            <div
              :if={reply.child_count > 0 or @ui.replying == {@post.id, reply.id}}
              class="ms-9 mt-2 grid gap-3"
            >
              <.more_replies
                count={reply.child_count - length(reply.children)}
                post={@post}
                parent={reply}
                ui={@ui}
              />
              <ul :if={reply.children != []} class="grid gap-3">
                <li :for={child <- reply.children} id={"reply-#{child.id}"}>
                  <.reply reply={child} post={@post} ui={@ui} can_answer={@can_answer} />
                </li>
              </ul>
              <.reply_form :if={@ui.replying == {@post.id, reply.id}} post={@post} ui={@ui} />
            </div>
          </li>
        </ul>

        <.reply_form :if={@ui.replying == {@post.id, nil}} post={@post} ui={@ui} />

        <div :if={@can_answer and @ui.replying == nil} class="flex items-center gap-2">
          <.avatar
            name={User.display_name(@ui.current_scope.user)}
            src={Paths.avatar(@ui.current_scope, @ui.current_scope.user)}
            size="sm"
          />
          <button
            id={"reply-open-#{@post.id}"}
            type="button"
            phx-click="reply"
            phx-value-post={@post.id}
            phx-target={@ui.myself}
            class="flex min-h-11 flex-1 items-center gap-2 rounded-full border border-line bg-surface px-4 text-start text-sm text-ink-muted transition-colors hover:border-ink-muted hover:text-ink focus-visible:outline-2 focus-visible:outline-primary"
          >
            {gettext("Write a reply…")}
          </button>
        </div>
      </section>
    </article>
    """
  end

  attr :post, :map, required: true
  attr :ui, :map, required: true

  # Una publicación en el tablón, compacta: el comienzo del texto, los
  # adjuntos y cómo va la conversación. Toda la tarjeta lleva a su página.
  defp post_card(%{post: %{kind: "content"}} = assigns), do: content_card(assigns)

  defp post_card(assigns) do
    %{post: post} = assigns

    assigns =
      assign(assigns,
        author: post.author,
        excerpt: excerpt(post),
        files: Enum.map(post.attachments, & &1.file),
        last_reply: List.last(post.replies)
      )

    ~H"""
    <article class="relative rounded-card border border-line bg-surface p-5 shadow-sm transition-colors duration-fast hover:border-ink-muted has-[a[data-open]:focus-visible]:outline-2 has-[a[data-open]:focus-visible]:outline-primary">
      <header class="mb-2 flex items-center gap-3">
        <.drag_handle :if={@ui.can_moderate} />
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
            <span
              :if={@files != []}
              id={"post-files-count-#{@post.id}"}
              class="inline-flex items-center gap-0.5"
              title={ngettext("%{count} attachment", "%{count} attachments", length(@files))}
            >
              · <.icon name="paperclip" class="size-4" /> {length(@files)}
              <span class="sr-only">
                {ngettext("%{count} attachment", "%{count} attachments", length(@files))}
              </span>
            </span>
            <.badge :if={@post.section} family="airampo">{@post.section.name}</.badge>
          </p>
        </div>
        <div class="relative z-10">
          <.post_menu post={@post} ui={@ui} />
        </div>
      </header>

      <.link
        navigate={Paths.course_post(@ui.current_scope, @ui.course, @post)}
        id={"post-open-#{@post.id}"}
        data-open
        class="line-clamp-3 text-ink outline-none after:absolute after:inset-0 after:rounded-card"
      >
        {if @excerpt == "", do: gettext("Open post"), else: @excerpt}
      </.link>

      <footer class="mt-3 flex flex-wrap items-center gap-x-4 gap-y-2 text-sm text-ink-muted">
        <span
          :for={file <- Enum.take(@files, 2)}
          class="inline-flex max-w-48 items-center gap-1 rounded-full border border-line px-2 py-0.5 text-xs"
        >
          <.icon name="paperclip" class="size-3.5 shrink-0" />
          <span class="truncate">{file.filename}</span>
        </span>
        <span :if={length(@files) > 2} class="text-xs">
          {gettext("+%{count} more", count: length(@files) - 2)}
        </span>
        <span
          :if={@post.reply_count > 0}
          id={"reply-summary-#{@post.id}"}
          class="inline-flex min-w-0 items-center gap-1"
        >
          <.icon name="chats-circle" class="size-4 shrink-0" />
          {ngettext("%{count} reply", "%{count} replies", @post.reply_count)}
          <span :if={@last_reply && @last_reply.author} class="truncate">
            · {gettext("last by %{name}", name: User.given_name(@last_reply.author))}
          </span>
        </span>
        <span :if={!@post.replies_enabled} class="inline-flex items-center gap-1">
          <.icon name="lock" class="size-4" /> {gettext("Replies are closed")}
        </span>
        <span
          class="ms-auto inline-flex items-center gap-1 font-semibold text-anil-deep"
          aria-hidden="true"
        >
          {gettext("Open")} <.icon name="arrow-right" class="size-4" />
        </span>
      </footer>
    </article>
    """
  end

  # Tarjeta de un elemento del contenido que se empezó a ver (ERS 4.3): quién
  # lo publicó y qué. Toda la tarjeta lleva al elemento; no tiene respuestas.
  defp content_card(assigns) do
    %{post: %{author: author, item: item}} = assigns
    name = (author && User.display_name(author)) || gettext("Former member")

    assigns =
      assign(assigns,
        line:
          case item.kind do
            "page" -> gettext("%{name} published a page", name: name)
            "material" -> gettext("%{name} published a material", name: name)
          end
      )

    ~H"""
    <article
      id={"content-card-#{@post.id}"}
      class="relative flex items-center gap-4 rounded-card border border-line bg-surface p-4 shadow-sm transition-colors duration-fast hover:border-ink-muted has-[a[data-open]:focus-visible]:outline-2 has-[a[data-open]:focus-visible]:outline-primary"
    >
      <.drag_handle :if={@ui.can_moderate} />
      <AmautaWeb.ContentComponents.kind_icon kind={@post.item.kind} />
      <div class="min-w-0 flex-1">
        <p class="text-sm text-ink-muted">
          {@line} ·
          <time datetime={DateTime.to_iso8601(@post.published_at)}>
            {Format.datetime(@post.published_at, @ui.timezone, :short)}
          </time>
        </p>
        <.link
          navigate={post_path(@ui, @post)}
          id={"post-open-#{@post.id}"}
          data-open
          class="block truncate font-semibold outline-none after:absolute after:inset-0 after:rounded-card"
        >
          {@post.item.title}
        </.link>
      </div>
      <div class="relative z-10">
        <.post_menu post={@post} ui={@ui} />
      </div>
    </article>
    """
  end

  attr :post, :map, required: true
  attr :ui, :map, required: true
  attr :pin, :map, required: true

  # Una fijada, en las novedades: una fila que lleva a su página. Quien
  # modera la ordena (arrastrándola o desde el menú) y le pone vencimiento.
  defp pinned_row(assigns) do
    assigns = assign(assigns, excerpt: excerpt(assigns.post))

    ~H"""
    <div>
      <div class="relative flex min-h-14 items-center gap-3 px-4 py-2 transition-colors duration-fast hover:bg-surface-sunken has-[a:focus-visible]:outline-2 has-[a:focus-visible]:-outline-offset-2 has-[a:focus-visible]:outline-primary">
        <.drag_handle :if={@ui.can_moderate} />
        <span class="inline-flex size-9 shrink-0 items-center justify-center rounded-control bg-anil-soft text-anil-deep">
          <.icon name="push-pin" class="size-4" />
        </span>
        <.link
          navigate={post_path(@ui, @post)}
          class="min-w-0 flex-1 truncate font-semibold outline-none after:absolute after:inset-0"
        >
          {if @excerpt == "", do: gettext("Open post"), else: @excerpt}
        </.link>
        <span class="hidden shrink-0 text-xs text-ink-muted sm:inline">
          {gettext("Pinned")}<span :if={@post.author}> · {User.given_name(@post.author)}</span>
          <span :if={@post.pin_expires_at}>
            · {gettext("until %{date}", date: Format.date(@post.pin_expires_at, @ui.timezone))}
          </span>
        </span>
        <div class="relative z-10">
          <.post_menu post={@post} ui={@ui} pin={@pin} />
        </div>
      </div>
      <div :if={@ui.can_moderate && @ui.pin_editing == @post.id} class="px-4">
        <.pin_expiry post={@post} ui={@ui} />
      </div>
    </div>
    """
  end

  attr :post, :map, required: true
  attr :ui, :map, required: true

  # Un elemento del contenido que se empezó a ver, en las novedades: qué es,
  # cómo se llama y cuándo se publicó. Lleva al elemento.
  defp news_row(assigns) do
    ~H"""
    <div class="relative flex min-h-14 items-center gap-3 px-4 py-2 transition-colors duration-fast hover:bg-surface-sunken has-[a:focus-visible]:outline-2 has-[a:focus-visible]:-outline-offset-2 has-[a:focus-visible]:outline-primary">
      <.drag_handle :if={@ui.can_moderate} />
      <AmautaWeb.ContentComponents.kind_icon kind={@post.item.kind} />
      <.link
        navigate={post_path(@ui, @post)}
        id={"post-open-#{@post.id}"}
        data-open
        class="min-w-0 flex-1 truncate font-semibold outline-none after:absolute after:inset-0"
      >
        {@post.item.title}
      </.link>
      <span class="hidden shrink-0 text-xs text-ink-muted sm:inline">
        {AmautaWeb.ContentComponents.kind_label(@post.item.kind)} ·
        <time datetime={DateTime.to_iso8601(@post.published_at)}>
          {Format.datetime(@post.published_at, @ui.timezone, :short)}
        </time>
      </span>
      <div :if={@ui.can_moderate} class="relative z-10">
        <.post_menu post={@post} ui={@ui} />
      </div>
    </div>
    """
  end

  # Adónde lleva una publicación del tablón: a su página o, si es la tarjeta
  # de un elemento del contenido, al elemento.
  defp post_path(ui, %{kind: "content", item: item}),
    do: Paths.course_item(ui.current_scope, ui.course, item)

  defp post_path(ui, post), do: Paths.course_post(ui.current_scope, ui.course, post)

  # El comienzo del texto, en una línea, para las vistas compactas.
  defp excerpt(%{kind: "content", item: item}), do: item.title

  defp excerpt(post) do
    post.body
    |> Amauta.RichText.to_text()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, 400)
  end

  # Manija para arrastrar a la zona de fijadas (solo quien modera).
  defp drag_handle(assigns) do
    ~H"""
    <span
      data-drag-handle
      draggable="true"
      aria-hidden="true"
      title={gettext("Drag to the pinned area")}
      class="relative z-10 -ms-2 hidden cursor-grab self-center text-ink-muted hover:text-ink md:block"
    >
      <.icon name="dots-six-vertical" class="size-5" />
    </span>
    """
  end

  attr :post, :map, required: true
  attr :ui, :map, required: true
  attr :pin, :map, default: nil

  # El menú «…» de una publicación. Editar solo está en su página: en el
  # tablón la publicación se ve recortada.
  defp post_menu(assigns) do
    %{post: post, ui: ui} = assigns
    mine = post.author_id == ui.current_scope.user.id

    assigns =
      assign(assigns,
        mine: mine,
        author: post.author,
        can_edit: mine and is_binary(ui.post_id),
        # Las tarjetas del contenido no llevan respuestas.
        can_toggle: post.kind == "post" and (mine or ui.can_moderate)
      )

    ~H"""
    <.dropdown
      :if={@mine or @ui.can_moderate}
      id={"post-menu-#{@post.id}"}
      label={gettext("Post options")}
    >
      <:trigger><.icon name="dots-three" class="size-5 text-ink-muted" /></:trigger>
      <.dropdown_item
        :if={@can_edit}
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
      <.dropdown_item
        :if={@pin && @ui.can_moderate}
        icon="calendar-blank"
        phx-click="edit_pin_expiry"
        phx-value-id={@post.id}
        phx-target={@ui.myself}
      >
        {gettext("Unpin on a date…")}
      </.dropdown_item>
      <.dropdown_item
        :if={@pin && @ui.can_moderate && !@pin.first}
        icon="arrow-up"
        phx-click="move_pin"
        phx-value-id={@post.id}
        phx-value-dir="up"
        phx-target={@ui.myself}
      >
        {gettext("Move up")}
      </.dropdown_item>
      <.dropdown_item
        :if={@pin && @ui.can_moderate && !@pin.last}
        icon="arrow-down"
        phx-click="move_pin"
        phx-value-id={@post.id}
        phx-value-dir="down"
        phx-target={@ui.myself}
      >
        {gettext("Move down")}
      </.dropdown_item>
      <.dropdown_item
        :if={@can_toggle}
        icon={if @post.replies_enabled, do: "lock", else: "chats-circle"}
        phx-click="toggle_replies"
        phx-value-post={@post.id}
        phx-value-enabled={to_string(!@post.replies_enabled)}
        phx-target={@ui.myself}
      >
        {if @post.replies_enabled, do: gettext("Close replies"), else: gettext("Open replies")}
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
    """
  end

  attr :post, :map, required: true
  attr :ui, :map, required: true

  # Para quien modera, en una fijada: la fecha en que deja de estarlo
  # (RF-TAB-006). Se abre desde el menú de la publicación; el orden también
  # está en el menú.
  defp pin_expiry(assigns) do
    expires = assigns.post.pin_expires_at

    assigns =
      assign(assigns,
        expires_on:
          expires &&
            expires |> DateTime.shift_zone!(assigns.ui.timezone) |> DateTime.to_date()
      )

    ~H"""
    <div class="mb-3 flex flex-wrap items-center gap-2 rounded-card bg-surface-sunken px-3 py-2 text-sm">
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
      <.button
        type="button"
        size="sm"
        variant="ghost"
        class="ms-auto"
        phx-click="close_pin_expiry"
        phx-target={@ui.myself}
      >
        {gettext("Done")}
      </.button>
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

  # Una respuesta: el contenido en una burbuja y, debajo y fuera de ella, la
  # fecha y las acciones, para que no se confundan con el texto.
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
        show_body: is_nil(reply.hidden_at) or mine or ui.can_moderate,
        has_menu: mine or ui.can_moderate,
        # Las anidadas cuelgan siempre de la de primer nivel.
        thread: reply.parent_id || reply.id
      )

    ~H"""
    <div class="flex items-start gap-2">
      <.avatar
        :if={@author}
        name={User.display_name(@author)}
        src={Paths.avatar(@ui.current_scope, @author)}
        size="sm"
      />
      <div class="min-w-0 flex-1">
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
          <.attach_field context={:edit_reply} ui={@ui} />
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

        <div
          :if={!@editing}
          class={[
            "rounded-card px-3 py-2",
            if(@hidden, do: "border border-dashed border-line", else: "bg-surface")
          ]}
        >
          <p class="flex flex-wrap items-center gap-x-2 text-sm font-semibold">
            {(@author && User.display_name(@author)) || gettext("Former member")}
            <.badge :if={@author && MapSet.member?(@ui.muted, @author.id)} family="nogal">
              {gettext("muted")}
            </.badge>
            <.badge :if={@hidden} family="nogal">{gettext("hidden")}</.badge>
          </p>
          <p :if={!@show_body} class="text-sm italic text-ink-muted">
            {gettext("This reply was hidden by the teaching team.")}
          </p>
          <.collapsible :if={@show_body} id={"reply-text-#{@reply.id}"}>
            <.rich_text id={"reply-body-#{@reply.id}"} doc={@reply.body} />
          </.collapsible>
        </div>

        <.attachment_list
          :if={@show_body and not @editing}
          id={"reply-files-#{@reply.id}"}
          files={Enum.map(@reply.attachments, & &1.file)}
          tenant={@ui.current_scope}
          class="mt-1"
        />

        <div :if={!@editing} class="flex flex-wrap items-center gap-x-3 ps-3 text-xs text-ink-muted">
          <time datetime={DateTime.to_iso8601(@reply.inserted_at)}>
            {Format.datetime(@reply.inserted_at, @ui.timezone, :short)}
          </time>
          <span :if={@reply.edited_at}>{gettext("edited")}</span>
          <button
            :if={@can_answer and @ui.replying == nil}
            type="button"
            phx-click="reply"
            phx-value-post={@post.id}
            phx-value-parent={@thread}
            phx-target={@ui.myself}
            class="-my-3 inline-flex min-h-11 items-center font-semibold hover:text-ink"
          >
            {gettext("Reply")}
          </button>
          <div :if={@has_menu} class="-my-3">
            <.dropdown id={"reply-menu-#{@reply.id}"} label={gettext("Reply options")}>
              <:trigger><.icon name="dots-three" class="size-4" /></:trigger>
              <.dropdown_item
                :if={@mine}
                icon="pencil-simple"
                phx-click="edit_reply"
                phx-value-id={@reply.id}
                phx-value-post={@post.id}
                phx-target={@ui.myself}
              >
                {gettext("Edit reply")}
              </.dropdown_item>
              <.dropdown_item
                :if={@ui.can_moderate}
                icon={if @hidden, do: "eye", else: "eye-slash"}
                phx-click="hide_reply"
                phx-value-id={@reply.id}
                phx-value-hidden={to_string(!@hidden)}
                phx-target={@ui.myself}
              >
                {if @hidden, do: gettext("Show reply"), else: gettext("Hide reply")}
              </.dropdown_item>
              <.mute_item :if={!@mine && @author} user={@author} post={@post} ui={@ui} />
              <.dropdown_item
                icon="trash"
                phx-click="delete_reply"
                phx-value-id={@reply.id}
                phx-target={@ui.myself}
                data-confirm={gettext("Delete this reply?")}
              >
                {gettext("Delete reply")}
              </.dropdown_item>
            </.dropdown>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :count, :integer, required: true
  attr :post, :map, required: true
  attr :parent, :map, default: nil
  attr :ui, :map, required: true

  # «Ver anteriores»: las respuestas que no se muestran de un hilo largo.
  defp more_replies(assigns) do
    ~H"""
    <button
      :if={@count > 0}
      type="button"
      phx-click="more_replies"
      phx-value-post={@post.id}
      phx-value-parent={@parent && @parent.id}
      phx-target={@ui.myself}
      class="inline-flex min-h-11 items-center gap-2 justify-self-start text-sm font-semibold text-ink-muted hover:text-ink"
    >
      <.icon name="chats-circle" class="size-4" />
      {ngettext("View %{count} earlier reply", "View %{count} earlier replies", @count)}
    </button>
    """
  end

  attr :context, :atom, required: true
  attr :ui, :map, required: true

  # Adjuntos de un formulario (RF-TAB-005): los ya subidos, para quitarlos,
  # y el botón para sumar más (hasta el máximo).
  defp attach_field(assigns) do
    files = assigns.ui.files[assigns.context]
    assigns = assign(assigns, files: files, room: length(files) < Feed.max_attachments())

    ~H"""
    <div :if={@ui.can_attach} class="mb-3 grid gap-2">
      <.attachment_list
        id={"feed-files-#{@context}"}
        files={@files}
        tenant={@ui.current_scope}
        remove={"remove_file:#{@context}"}
        target={@ui.myself}
      />
      <.live_component
        :if={@room}
        module={AmautaWeb.Components.DirectUpload}
        id={"feed-upload-#{String.replace(to_string(@context), "_", "-")}"}
        current_scope={@ui.current_scope}
        purpose="feed_attachment"
        owner_id={@ui.course.id}
        variant="button"
        label={gettext("Attach file")}
        hint={gettext("Up to %{count} files per post.", count: Feed.max_attachments())}
      />
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
    >
      <.rich_text_editor
        id={"reply-editor-#{@post.id}-#{@ui.reply_key}"}
        field={@ui.reply_form[:body]}
        label={gettext("Your reply")}
        placeholder={gettext("Write a reply. Use «@» to mention someone.")}
        mentions={@ui.mentions}
      />
      <.attach_field context={:reply} ui={@ui} />
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
end
