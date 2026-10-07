defmodule AmautaWeb.PeopleExportController do
  @moduledoc "Descarga del directorio filtrado en CSV (RF-IMP-005), auditada por la acción."
  use AmautaWeb, :controller

  alias Amauta.Actions
  alias Amauta.Accounts.Actions.ExportUsers

  def export(conn, params) do
    scope = conn.assigns.current_scope

    case Actions.run(ExportUsers, scope, Map.take(params, ~w(q status role))) do
      {:ok, %{csv: csv}} ->
        filename = "#{scope.institution.slug}-personas-#{Date.utc_today()}.csv"

        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
        # BOM: Excel abre el UTF-8 con los acentos bien.
        |> send_resp(200, [<<0xEF, 0xBB, 0xBF>>, csv])

      {:error, :forbidden} ->
        raise AmautaWeb.ForbiddenError
    end
  end
end
