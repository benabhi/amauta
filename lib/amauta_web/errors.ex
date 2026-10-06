defmodule AmautaWeb.NotFoundError do
  @moduledoc "Recurso inexistente dentro de la institución (404)."
  defexception message: "not found", plug_status: 404
end

defmodule AmautaWeb.ForbiddenError do
  @moduledoc "Falta de permiso (403)."
  defexception message: "forbidden", plug_status: 403
end
