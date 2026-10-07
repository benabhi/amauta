defmodule AmautaWeb.NotFoundError do
  @moduledoc "Recurso inexistente, por ejemplo una institución desconocida (404)."
  defexception message: "not found", plug_status: 404
end

defmodule AmautaWeb.InstitutionSuspendedError do
  @moduledoc "La institución existe pero está suspendida (403)."
  defexception message: "institution suspended", plug_status: 403
end

defmodule AmautaWeb.ForbiddenError do
  @moduledoc "La persona no tiene permiso para lo que pidió (403)."
  defexception message: "forbidden", plug_status: 403
end
