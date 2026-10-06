defmodule Amauta.Authorization.Permissions do
  @moduledoc """
  Catálogo de permisos atómicos (RF-ROL-001, Anexo B). Para el spike se
  incluye solo lo que usa la porción vertical.
  """

  @catalog %{
    "course.view" => %{risk: :low, description: "Ver el curso"},
    "course.feed.post" => %{risk: :low, description: "Publicar en el tablón"},
    "course.feed.reply" => %{risk: :low, description: "Responder en el tablón"},
    "course.feed.pin" => %{risk: :low, description: "Fijar publicaciones"},
    "course.feed.moderate" => %{risk: :medium, description: "Ocultar, eliminar y silenciar"}
  }

  def all, do: Map.keys(@catalog)
  def get(permission), do: Map.fetch(@catalog, permission)
  def exists?(permission), do: Map.has_key?(@catalog, permission)
end
