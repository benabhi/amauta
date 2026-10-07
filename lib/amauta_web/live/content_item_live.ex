defmodule AmautaWeb.ContentItemLive do
  @moduledoc """
  Un elemento del contenido del curso (RF-CON-002): verlo (`:show`) y, para
  quien gestiona el contenido, crearlo (`:new`, con `unit` y `kind`) o
  editarlo (`:edit`).

  Una página se arma con el editor de bloques. Un material lleva archivos
  (subida directa al almacenamiento) y un enlace opcional, con una
  descripción.
  """
  use AmautaWeb, :live_view

  import AmautaWeb.ContentComponents

  alias Amauta.{Actions, Content, Courses, Files}
  alias Amauta.Content.Actions.{CreateItem, SetItemDone, UpdateItem}
  alias Amauta.Content.Item
  alias AmautaWeb.Components.DirectUpload
  alias AmautaWeb.Paths

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope
    course = Courses.get_by_slug(scope, slug) || raise AmautaWeb.NotFoundError

    unless Content.can_view?(scope, course) and
             (course.status != "draft" or
                Amauta.Authorization.can?(scope, "course.update", course)) do
      raise AmautaWeb.ForbiddenError
    end

    {:ok,
     assign(socket,
       course: course,
       can_manage: Content.can_manage?(scope, course),
       timezone: scope.user.timezone || scope.institution.timezone,
       files: [],
       saved_file_ids: []
     )}
  end

  @impl true
  def handle_params(params, _url, socket),
    do: {:noreply, apply_action(socket, socket.assigns.live_action, params)}

  defp apply_action(socket, :show, %{"item_id" => id}) do
    %{current_scope: scope, course: course} = socket.assigns
    item = Content.get_item(scope, course, id) || raise AmautaWeb.NotFoundError
    units = Content.list_units(scope, course)
    {prev, next} = Content.neighbors(units, item.id)
    done = Content.completed_ids(scope, course)

    assign(socket,
      page_title: item.title,
      item: item,
      unit: item.unit,
      files: Enum.map(item.files, & &1.file),
      units: units,
      prev: prev,
      next: next,
      done: done,
      is_done: MapSet.member?(done, item.id),
      tracks: Content.tracks_progress?(scope, course)
    )
  end

  defp apply_action(socket, :new, params) do
    %{current_scope: scope, course: course} = socket.assigns
    require_manage!(socket)

    unit =
      (params["unit"] && Content.get_unit(scope, course, params["unit"])) ||
        raise AmautaWeb.NotFoundError

    kind =
      if params["kind"] in Item.kinds(), do: params["kind"], else: raise(AmautaWeb.NotFoundError)

    socket
    |> assign(
      page_title: new_title(kind),
      item: %Item{kind: kind, unit_id: unit.id},
      unit: unit,
      files: [],
      saved_file_ids: []
    )
    |> assign_form(%{"visibility" => "visible", "announce" => true})
  end

  defp apply_action(socket, :edit, %{"item_id" => id}) do
    %{current_scope: scope, course: course, timezone: tz} = socket.assigns
    require_manage!(socket)
    item = Content.get_item(scope, course, id) || raise AmautaWeb.NotFoundError
    files = Enum.map(item.files, & &1.file)

    socket
    |> assign(
      page_title: item.title,
      item: item,
      unit: item.unit,
      files: files,
      saved_file_ids: Enum.map(files, & &1.id)
    )
    |> assign_form(%{
      "title" => item.title,
      "body" => item.body,
      "url" => item.url,
      "visibility" => item.visibility,
      "publish_local" => to_local(item.publish_at, tz),
      "announce" => item.announce
    })
  end

  defp require_manage!(socket) do
    unless socket.assigns.can_manage, do: raise(AmautaWeb.ForbiddenError)
  end

  defp new_title("page"), do: gettext("New page")
  defp new_title("material"), do: gettext("New material")

  defp assign_form(socket, params, errors \\ []) do
    errors =
      Enum.map(errors, fn
        {:publish_at, error} -> {:publish_local, error}
        other -> other
      end)

    assign(socket,
      form: to_form(params, as: "item", errors: errors, action: if(errors != [], do: :validate))
    )
  end

  ## Finalización (RF-CON-006)

  @impl true
  def handle_event("toggle_done", _params, socket) do
    %{current_scope: scope, item: item, is_done: is_done, done: done} = socket.assigns

    case Actions.run(SetItemDone, scope, %{"item_id" => item.id, "done" => !is_done}) do
      {:ok, _} ->
        done = if is_done, do: MapSet.delete(done, item.id), else: MapSet.put(done, item.id)
        {:noreply, assign(socket, done: done, is_done: !is_done)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("That could not be done."))}
    end
  end

  ## Edición

  def handle_event("change", %{"item" => params}, socket),
    do: {:noreply, assign_form(socket, params)}

  def handle_event("save", %{"item" => params}, socket) do
    %{current_scope: scope, item: item, timezone: tz} = socket.assigns

    input =
      params
      |> visibility_params(tz)
      |> then(fn input ->
        if item.kind == "material",
          do: Map.put(input, "file_ids", Enum.map(socket.assigns.files, & &1.id)),
          else: Map.delete(input, "url")
      end)

    result =
      case socket.assigns.live_action do
        :new ->
          Actions.run(
            CreateItem,
            scope,
            Map.merge(input, %{"unit_id" => item.unit_id, "kind" => item.kind})
          )

        :edit ->
          Actions.run(UpdateItem, scope, Map.put(input, "item_id", item.id))
      end

    case result do
      {:ok, saved} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Saved."))
         |> push_navigate(to: Paths.course_item(scope, socket.assigns.course, saved))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, params, changeset.errors)}

      {:error, reason} when reason in [:too_many_files, :invalid_file] ->
        {:noreply, put_flash(socket, :error, gettext("Check the files and try again."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("That could not be done."))}
    end
  end

  # Quitar un archivo antes de guardar. Si todavía no estaba en el material,
  # se descarta ya; si estaba, se descarta al guardar.
  def handle_event("remove_file", %{"id" => id}, socket) do
    %{files: files, saved_file_ids: saved, current_scope: scope} = socket.assigns
    {removed, kept} = Enum.split_with(files, &(&1.id == id))

    for file <- removed, file.id not in saved, do: Files.discard(scope, file)

    {:noreply, assign(socket, files: kept)}
  end

  @impl true
  def handle_info({DirectUpload, "content-upload", {:uploaded, file}}, socket),
    do:
      {:noreply,
       assign(socket, files: Enum.take(socket.assigns.files ++ [file], Content.max_files()))}

  ## Vista

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width="lg" active={:courses}>
      <nav
        aria-label={gettext("Breadcrumb")}
        class="mb-2 flex flex-wrap items-center gap-1 text-sm text-ink-muted"
      >
        <.link
          navigate={Paths.course(@current_scope, @course, :content)}
          class="hover:text-ink hover:underline"
        >
          {@course.name}
        </.link>
        <.icon name="caret-right" class="size-3.5" />
        <span>{@unit.title}</span>
      </nav>

      <div class="grid gap-8 lg:grid-cols-[16rem_minmax(0,1fr)]">
        <aside class="hidden lg:block">
          <div class="sticky top-20 max-h-[calc(100vh-6rem)] overflow-y-auto pe-2">
            <.content_nav
              units={@units}
              current_id={@item.id}
              done={@done}
              tracks={@tracks}
              current_scope={@current_scope}
              course={@course}
            />
          </div>
        </aside>

        <div class="min-w-0">
          <.header>
            <span class="flex items-center gap-3">
              <.kind_icon kind={@item.kind} />
              <span>{@item.title}</span>
            </span>
            <:subtitle>
              <span class="flex flex-wrap items-center gap-2">
                {kind_label(@item.kind)}
                <.visibility_badge subject={@item} timezone={@timezone} />
                <.visibility_badge subject={@unit} timezone={@timezone} />
              </span>
            </:subtitle>
            <:actions>
              <.button
                :if={@can_manage}
                id="content-item-edit"
                variant="secondary"
                icon="pencil-simple"
                navigate={Paths.edit_course_item(@current_scope, @course, @item)}
              >
                {gettext("Edit")}
              </.button>
            </:actions>
          </.header>

          <article id="content-item" class="grid gap-6">
            <.card :if={not Amauta.RichText.blank?(@item.body)}>
              <.rich_text id="content-item-body" doc={@item.body} />
            </.card>

            <a
              :if={@item.url}
              id="content-item-link"
              href={@item.url}
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex min-h-11 max-w-full items-center gap-2 justify-self-start rounded-control border border-line bg-surface px-4 font-semibold text-anil-deep hover:border-primary"
            >
              <.icon name="link" class="size-5 shrink-0" />
              <span class="truncate">{link_label(@item.url)}</span>
            </a>

            <.file_viewer
              :for={file <- Enum.filter(@files, &viewable?/1)}
              file={file}
              tenant={@current_scope}
            />
            <.attachment_list
              id="content-item-files"
              files={Enum.reject(@files, &viewable?/1)}
              tenant={@current_scope}
            />
          </article>

          <footer class="mt-8 grid gap-4 border-t border-line pt-6">
            <div :if={@tracks} class="flex justify-center">
              <.button
                id="content-item-done"
                variant={if @is_done, do: "secondary", else: "primary"}
                icon={if @is_done, do: "check-circle", else: "check"}
                phx-click="toggle_done"
                aria-pressed={to_string(@is_done)}
              >
                {if @is_done, do: gettext("Done · undo"), else: gettext("Mark as done")}
              </.button>
            </div>

            <nav
              aria-label={gettext("Previous and next")}
              class="grid grid-cols-2 gap-3"
            >
              <.link
                :if={@prev}
                id="content-item-prev"
                navigate={Paths.course_item(@current_scope, @course, @prev)}
                class="group flex min-h-16 flex-col justify-center rounded-card border border-line bg-surface px-4 py-2 hover:border-primary"
              >
                <span class="flex items-center gap-1 text-xs text-ink-muted">
                  <.icon name="arrow-left" class="size-3.5" /> {gettext("Previous")}
                </span>
                <span class="truncate font-semibold">{@prev.title}</span>
              </.link>
              <span :if={!@prev}></span>
              <.link
                :if={@next}
                id="content-item-next"
                navigate={Paths.course_item(@current_scope, @course, @next)}
                class="group flex min-h-16 flex-col items-end justify-center rounded-card border border-line bg-surface px-4 py-2 text-end hover:border-primary"
              >
                <span class="flex items-center gap-1 text-xs text-ink-muted">
                  {gettext("Next")} <.icon name="arrow-right" class="size-3.5" />
                </span>
                <span class="max-w-full truncate font-semibold">{@next.title}</span>
              </.link>
              <.link
                :if={!@next}
                navigate={Paths.course(@current_scope, @course, :content)}
                class="flex min-h-16 flex-col items-end justify-center rounded-card border border-dashed border-line px-4 py-2 text-end text-ink-muted hover:border-primary hover:text-ink"
              >
                <span class="text-xs">{gettext("You reached the end")}</span>
                <span class="font-semibold">{gettext("Back to content")}</span>
              </.link>
            </nav>
          </footer>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width="lg" active={:courses}>
      <.header>
        {if @live_action == :new,
          do: new_title(@item.kind),
          else: gettext("Edit «%{title}»", title: @item.title)}
        <:subtitle>{@course.name} · {@unit.title}</:subtitle>
      </.header>

      <.card>
        <.form for={@form} id="content-item-form" phx-change="change" phx-submit="save">
          <.input field={@form[:title]} label={gettext("Title")} required />
          <.input
            :if={@item.kind == "material"}
            field={@form[:url]}
            type="url"
            label={gettext("Link (optional)")}
            placeholder="https://"
          />
          <.rich_text_editor
            id="content-item-editor"
            field={@form[:body]}
            label={
              if @item.kind == "page", do: gettext("Content"), else: gettext("Description (optional)")
            }
            placeholder={
              if @item.kind == "page",
                do:
                  gettext("Write the page. Type «/» to add titles, lists, code, formulas and more."),
                else: gettext("What it is and how to use it.")
            }
          />
          <div :if={@item.kind == "material"} class="mb-4 grid gap-2">
            <span class="text-sm font-semibold">{gettext("Files")}</span>
            <.attachment_list
              id="content-item-files"
              files={@files}
              tenant={@current_scope}
              remove="remove_file"
            />
            <.live_component
              :if={length(@files) < Content.max_files()}
              module={DirectUpload}
              id="content-upload"
              current_scope={@current_scope}
              purpose="content_material"
              owner_id={@course.id}
              label={gettext("Add a file")}
              hint={
                gettext("Documents, images, audio or video. Up to %{count} files.",
                  count: Content.max_files()
                )
              }
            />
          </div>
          <.visibility_fields form={@form} timezone={@timezone} />
          <.input
            field={@form[:announce]}
            type="checkbox"
            label={gettext("Announce it in the feed when students can see it")}
          />
          <div class="flex gap-2">
            <.button phx-disable-with={gettext("Saving...")}>{gettext("Save")}</.button>
            <.button
              variant="ghost"
              navigate={
                if @live_action == :new,
                  do: Paths.course(@current_scope, @course, :content),
                  else: Paths.course_item(@current_scope, @course, @item)
              }
            >
              {gettext("Cancel")}
            </.button>
          </div>
        </.form>
      </.card>
    </Layouts.app>
    """
  end

  # El dominio del enlace, que dice más que la dirección entera.
  defp link_label(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> String.replace_prefix(host, "www.", "")
      _ -> url
    end
  end
end
