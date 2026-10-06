defmodule Amauta.Authorization.Roles do
  @moduledoc "Roles de sistema (Anexo C), reducidos a los permisos del spike."
  alias Amauta.Authorization.Permissions

  @roles %{
    "institution_admin" => :all,
    "teacher" =>
      ~w(course.view course.feed.post course.feed.reply course.feed.pin course.feed.moderate),
    "assistant" => ~w(course.view course.feed.reply),
    "student" => ~w(course.view course.feed.reply),
    "observer" => ~w(course.view)
  }

  def all, do: Map.keys(@roles)

  def permissions(role) do
    case Map.fetch!(@roles, role) do
      :all -> Permissions.all()
      list -> list
    end
  end
end
