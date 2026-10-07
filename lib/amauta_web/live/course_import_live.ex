defmodule AmautaWeb.CourseImportLive do
  @moduledoc """
  Matriculación desde CSV (RF-MAT-001): subir el archivo, simular (sin
  cambios) y aplicar. Cada fila trae el email de una persona de la
  institución y, opcionalmente, su rol y su comisión. Exige
  `course.people.enroll` en el curso (la acción lo verifica de nuevo).
  """
  use AmautaWeb, :live_view

  alias Amauta.{Actions, Authorization, Courses}
  alias Amauta.Authorization.Roles
  alias Amauta.Enrollments.Actions.ImportEnrollments
  alias Amauta.Enrollments.Import
  alias AmautaWeb.Paths

  @max_size 5_000_000

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope
    course = Courses.get_by_slug(scope, slug) || raise AmautaWeb.NotFoundError

    unless course.status != "archived" and
             Authorization.can?(scope, "course.people.enroll", course) do
      raise AmautaWeb.ForbiddenError
    end

    {:ok,
     socket
     |> assign(page_title: gettext("Enroll from CSV"), course: course)
     |> assign(step: :upload, plan: nil, error: nil, result: nil)
     |> allow_upload(:csv, accept: ~w(.csv text/csv), max_entries: 1, max_file_size: @max_size)}
  end

  @impl true
  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("read", _params, socket) do
    %{current_scope: scope, course: course} = socket.assigns

    content =
      consume_uploaded_entries(socket, :csv, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    with [binary] <- content,
         {:ok, csv} <- Import.parse(binary),
         {:ok, plan} <- Import.plan(scope, course, csv) do
      {:noreply, assign(socket, step: :review, plan: plan, error: nil)}
    else
      [] -> {:noreply, assign(socket, error: gettext("Choose a CSV file first."))}
      {:error, reason} -> {:noreply, assign(socket, error: read_error(reason))}
    end
  end

  def handle_event("apply", _params, socket) do
    %{current_scope: scope, course: course, plan: plan} = socket.assigns
    params = %{"course_id" => course.id, "rows" => Import.rows_to_apply(plan)}

    case Actions.run(ImportEnrollments, scope, params) do
      {:ok, result} ->
        {:noreply, assign(socket, step: :done, result: result)}

      {:error, :forbidden} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("You can't enroll some of those roles. Nothing was changed.")
         )}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("The import could not be applied. Nothing was changed.")
         )}
    end
  end

  def handle_event("restart", _params, socket),
    do: {:noreply, assign(socket, step: :upload, plan: nil, result: nil, error: nil)}

  defp read_error(:no_email),
    do: gettext("The file needs an «email» column to know who to enroll.")

  defp read_error(:not_utf8),
    do: gettext("The file is not in UTF-8. Save it as «CSV UTF-8» and try again.")

  defp read_error(:empty), do: gettext("The file is empty.")

  defp read_error(:too_many_rows),
    do: gettext("The file has more than 5,000 rows. Split it into smaller files.")

  defp read_error(_), do: gettext("The file could not be read as CSV.")

  defp row_error(:missing_email), do: gettext("the email is missing")
  defp row_error(:unknown_user), do: gettext("nobody in the institution has that email")
  defp row_error(:repeated), do: gettext("the email is repeated in the file")
  defp row_error(:unknown_role), do: gettext("the role is not recognized")
  defp row_error(:unknown_section), do: gettext("there is no section with that name")

  defp upload_error(:too_large), do: gettext("The file is too big (maximum 5 MB).")
  defp upload_error(:not_accepted), do: gettext("Choose a .csv file.")
  defp upload_error(_), do: gettext("The file could not be uploaded.")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:courses}>
      <.header>
        {gettext("Enroll from CSV")}
        <:subtitle>{@course.name}</:subtitle>
        <:actions>
          <.button
            variant="ghost"
            icon="arrow-left"
            navigate={Paths.course(@current_scope, @course, :people)}
          >
            {gettext("Back")}
          </.button>
        </:actions>
      </.header>

      <.card :if={@step == :upload}>
        <:header>{gettext("1. Choose the file")}</:header>
        <p class="mb-4 text-sm text-ink-muted">
          {gettext_term(
            @current_scope,
            :section,
            "One person per row. Columns: email (required), role and %{term} (optional; by default, student and no %{term}). The people must already exist in the institution."
          )}
        </p>
        <form id="upload_form" phx-submit="read" phx-change="validate_upload">
          <.live_file_input
            upload={@uploads.csv}
            class="mb-4 block w-full text-sm file:me-3 file:rounded-control file:border-0 file:bg-anil-soft file:px-3 file:py-2 file:font-semibold file:text-anil-deep"
          />
          <.error :for={err <- upload_errors(@uploads.csv)}>{upload_error(err)}</.error>
          <.error :if={@error}>{@error}</.error>
          <.button icon="arrow-right" class="mt-2">{gettext("Read file")}</.button>
        </form>
      </.card>

      <.card :if={@step == :review}>
        <:header>{gettext("2. Simulation")}</:header>
        <% summary = Import.summary(@plan) %>
        <div class="mb-4 flex flex-wrap gap-2">
          <.badge family="chilca" icon="plus">
            {ngettext("%{count} to enroll", "%{count} to enroll", summary.enroll)}
          </.badge>
          <.badge family="anil">
            {ngettext("%{count} already enrolled", "%{count} already enrolled", summary.already)}
          </.badge>
          <.badge :if={summary.error > 0} family="cochinilla" icon="warning">
            {ngettext("%{count} row with errors", "%{count} rows with errors", summary.error)}
          </.badge>
        </div>

        <ul
          :if={summary.error > 0}
          id="import_errors"
          class="mb-4 max-h-48 space-y-1 overflow-y-auto text-sm"
        >
          <li :for={row <- Enum.filter(@plan, &(&1.status == :error)) |> Enum.take(30)}>
            <span class="font-mono text-ink-muted">{gettext("Row %{line}", line: row.line)}:</span>
            {row.email} — {Enum.map_join(row.errors, "; ", &row_error/1)}
          </li>
        </ul>

        <ul id="import_preview" class="mb-4 divide-y divide-line text-sm">
          <li
            :for={row <- Enum.filter(@plan, &(&1.status == :enroll)) |> Enum.take(10)}
            class="flex justify-between gap-3 py-1.5"
          >
            <span class="truncate">{row.email}</span>
            <span class="text-ink-muted">{Roles.name(row.role)}</span>
          </li>
        </ul>

        <div class="flex gap-2">
          <.button
            :if={summary.enroll > 0}
            phx-click="apply"
            phx-disable-with={gettext("Enrolling...")}
            icon="check"
          >
            {ngettext("Enroll %{count} person", "Enroll %{count} people", summary.enroll)}
          </.button>
          <.button variant="ghost" phx-click="restart">{gettext("Choose another file")}</.button>
        </div>
      </.card>

      <.card :if={@step == :done}>
        <:header>{gettext("Done")}</:header>
        <p class="mb-4">
          {ngettext(
            "%{count} person was enrolled.",
            "%{count} people were enrolled.",
            @result.enrolled
          )}
        </p>
        <div class="flex gap-2">
          <.button navigate={Paths.course(@current_scope, @course, :people)}>
            {gettext("See people")}
          </.button>
          <.button variant="ghost" phx-click="restart">{gettext("Import another file")}</.button>
        </div>
      </.card>
    </Layouts.app>
    """
  end
end
