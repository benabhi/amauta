defmodule AmautaWeb.FileController do
  @moduledoc """
  Descarga de archivos (RF-ARC-002): verifica el permiso en cada pedido y
  redirige a una URL prefirmada de pocos minutos. El contenido nunca pasa
  por la aplicación. Con `?download=1`, el navegador lo guarda con su
  nombre original; si no, lo muestra (por ejemplo, una foto de perfil).
  """
  use AmautaWeb, :controller

  alias Amauta.Files
  alias Amauta.Files.Purpose

  def show(conn, %{"id" => id} = params) do
    scope = conn.assigns.current_scope

    with %{} = file <- Files.get(scope, id),
         true <- Purpose.can_view?(scope, file),
         {:ok, url} <- Files.download_url(file, download: params["download"] == "1") do
      conn
      # La URL vence en minutos: que nadie la guarde.
      |> put_resp_header("cache-control", "private, no-store")
      |> redirect(external: url)
    else
      _ -> raise AmautaWeb.NotFoundError
    end
  end
end
