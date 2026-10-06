defmodule AmautaWeb.PeopleImportLive do
  @moduledoc """
  Importación de personas desde CSV (RF-USR-004, RF-IMP-006): subir el
  archivo, revisar el mapeo de columnas, simular (sin cambios) y aplicar.
  El reporte de errores se puede descargar.
  """
  use AmautaWeb, :live_view

  alias Amauta.{Actions, Authorization}
  alias Amauta.Accounts.Import
  alias Amauta.Accounts.Actions.ImportUsers
  alias AmautaWeb.Paths

  @max_size 5_000_000

  @impl true
  def mount(_params, _session, socket) do
    if Authorization.can?(socket.assigns.current_scope, "institution.users.manage") do
      {:ok,
       socket
       |> assign(
         page_title: gettext("Import people"),
         step: :upload,
         csv: nil,
         mapping: %{},
         plan: nil
       )
       |> assign(send_invitations: true, error: nil, result: nil)
       |> allow_upload(:csv, accept: ~w(.csv text/csv), max_entries: 1, max_file_size: @max_size)}
    else
      raise AmautaWeb.ForbiddenError
    end
  end

  @impl true
  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("read", _params, socket) do
    content =
      consume_uploaded_entries(socket, :csv, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case content do
      [binary] ->
        case Import.parse(binary) do
          {:ok, csv} ->
            mapping = Import.guess_mapping(csv.headers)

            {:noreply,
             socket |> assign(step: :review, csv: csv, mapping: mapping, error: nil) |> simulate()}

          {:error, reason} ->
            {:noreply, assign(socket, error: parse_error(reason))}
        end

      [] ->
        {:noreply, assign(socket, error: gettext("Choose a CSV file first."))}
    end
  end

  def handle_event("map", %{"mapping" => mapping} = params, socket) do
    mapping =
      for field <- Import.fields(), into: %{} do
        case Integer.parse(mapping[Atom.to_string(field)] || "") do
          {index, _} -> {field, index}
          :error -> {field, nil}
        end
      end

    {:noreply,
     socket
     |> assign(mapping: mapping, send_invitations: params["send_invitations"] == "true")
     |> simulate()}
  end

  def handle_event("apply", _params, socket) do
    rows = for %{status: :create, attrs: attrs} <- socket.assigns.plan, do: attrs

    params = %{"rows" => rows, "send_invitations" => socket.assigns.send_invitations}

    case Actions.run(ImportUsers, socket.assigns.current_scope, params) do
      {:ok, %{created: created, skipped: skipped}} ->
        {:noreply,
         assign(socket, step: :done, result: %{created: length(created), skipped: skipped})}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("The import could not be applied. Nothing was changed."))
         |> simulate()}
    end
  end

  def handle_event("restart", _params, socket) do
    {:noreply, assign(socket, step: :upload, csv: nil, plan: nil, result: nil, error: nil)}
  end

  defp simulate(socket) do
    %{csv: csv, mapping: mapping, current_scope: scope} = socket.assigns

    if Enum.all?([:first_name, :last_name, :email], &is_integer(mapping[&1])) do
      assign(socket, plan: Import.plan(scope, csv.rows, mapping))
    else
      assign(socket, plan: nil)
    end
  end

  defp parse_error(:not_utf8),
    do: gettext("The file is not in UTF-8. Save it as «CSV UTF-8» and try again.")

  defp parse_error(:empty), do: gettext("The file is empty.")

  defp parse_error(:too_many_rows),
    do: gettext("The file has more than 5,000 rows. Split it into smaller files.")

  defp parse_error(_), do: gettext("The file could not be read as CSV.")

  defp field_label(:first_name), do: gettext("First name")
  defp field_label(:last_name), do: gettext("Last name")
  defp field_label(:email), do: gettext("Email")
  defp field_label(:preferred_name), do: gettext("Preferred name")

  defp report_href(plan) do
    "data:text/csv;charset=utf-8," <>
      URI.encode(Import.error_report(plan, &field_label/1), &URI.char_unreserved?/1)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:people}>
      <.header>
        {gettext("Import people")}
        <:subtitle>{gettext("From a CSV file with one person per row.")}</:subtitle>
        <:actions>
          <.button variant="ghost" icon="arrow-left" navigate={Paths.people(@current_scope)}>
            {gettext("Back to people")}
          </.button>
        </:actions>
      </.header>

      <.card :if={@step == :upload}>
        <:header>{gettext("1. Choose the file")}</:header>
        <p class="mb-4 text-sm text-ink-muted">
          {gettext(
            "The first row must have the column names. We recognize, among others: nombre, apellido, email and nombre preferido."
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

      <div :if={@step == :review} class="flex flex-col gap-6">
        <.card>
          <:header>{gettext("2. Check the columns")}</:header>
          <.form for={%{}} as={:mapping} id="mapping_form" phx-change="map">
            <div class="grid gap-x-4 sm:grid-cols-2">
              <.input
                :for={field <- Amauta.Accounts.Import.fields()}
                name={"mapping[#{field}]"}
                type="select"
                label={field_label(field)}
                value={@mapping[field]}
                prompt={gettext("(not imported)")}
                options={Enum.with_index(@csv.headers)}
              />
            </div>
            <input type="hidden" name="send_invitations" value="false" />
            <.input
              name="send_invitations"
              type="checkbox"
              value={@send_invitations}
              label={gettext("Send the invitations by email")}
            />
          </.form>
        </.card>

        <.card>
          <:header>{gettext("3. Simulation")}</:header>
          <p :if={!@plan} class="text-sm text-ink-muted">
            {gettext("Choose the columns for first name, last name and email to simulate.")}
          </p>
          <div :if={@plan}>
            <% summary = Amauta.Accounts.Import.summary(@plan) %>
            <div class="mb-4 flex flex-wrap gap-2">
              <.badge family="chilca" icon="plus">
                {ngettext("%{count} new person", "%{count} new people", summary.create)}
              </.badge>
              <.badge family="anil">
                {ngettext("%{count} already exists", "%{count} already exist", summary.exists)}
              </.badge>
              <.badge :if={summary.error > 0} family="cochinilla" icon="warning">
                {ngettext("%{count} row with errors", "%{count} rows with errors", summary.error)}
              </.badge>
            </div>

            <div :if={summary.error > 0} class="mb-4">
              <ul class="mb-2 max-h-48 space-y-1 overflow-y-auto text-sm">
                <li :for={row <- Enum.filter(@plan, &(&1.status == :error)) |> Enum.take(20)}>
                  <span class="font-mono text-ink-muted">{gettext("Row %{line}", line: row.line)}:</span>
                  {Enum.map_join(row.errors, "; ", fn {field, message} ->
                    "#{field_label(field)} #{message}"
                  end)}
                </li>
              </ul>
              <a
                href={report_href(@plan)}
                download="errores-importacion.csv"
                class="text-sm font-semibold text-anil-deep underline"
              >
                {gettext("Download the error report")}
              </a>
              <p class="mt-1 text-sm text-ink-muted">
                {gettext("Rows with errors are skipped. You can fix them and import the file again.")}
              </p>
            </div>

            <div class="flex gap-2">
              <.button
                :if={summary.create > 0}
                phx-click="apply"
                phx-disable-with={gettext("Importing...")}
                icon="check"
              >
                {ngettext("Import %{count} person", "Import %{count} people", summary.create)}
              </.button>
              <.button variant="ghost" phx-click="restart">{gettext("Choose another file")}</.button>
            </div>
          </div>
        </.card>
      </div>

      <.card :if={@step == :done}>
        <:header>{gettext("Import finished")}</:header>
        <p class="mb-4">
          {ngettext("%{count} person was added.", "%{count} people were added.", @result.created)}
          {ngettext("%{count} already existed.", "%{count} already existed.", @result.skipped)}
        </p>
        <div class="flex gap-2">
          <.button navigate={Paths.people(@current_scope)}>{gettext("See people")}</.button>
          <.button variant="ghost" phx-click="restart">{gettext("Import another file")}</.button>
        </div>
      </.card>
    </Layouts.app>
    """
  end

  defp upload_error(:too_large), do: gettext("The file is too big (maximum 5 MB).")
  defp upload_error(:not_accepted), do: gettext("Choose a .csv file.")
  defp upload_error(_), do: gettext("The file could not be uploaded.")
end
