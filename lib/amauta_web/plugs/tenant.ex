defmodule AmautaWeb.Plugs.Tenant do
  @moduledoc """
  Resuelve la institución de la solicitud (modo ruta: el primer segmento) y
  la asigna en `:current_institution`. Una institución desconocida da 404 y
  una suspendida, 403.
  """
  import Plug.Conn

  alias Amauta.Platform
  alias Amauta.Platform.Institution

  def init(opts), do: opts

  def call(%Plug.Conn{path_params: %{"institution" => slug}} = conn, _opts) do
    assign(conn, :current_institution, resolve!(slug))
  end

  @doc "Institución activa por slug; si no, lanza la excepción que corresponde."
  def resolve!(slug) do
    case Platform.get_institution_by_slug(slug) do
      %Institution{status: "active"} = institution -> institution
      %Institution{} -> raise AmautaWeb.InstitutionSuspendedError
      nil -> raise AmautaWeb.NotFoundError
    end
  end
end
