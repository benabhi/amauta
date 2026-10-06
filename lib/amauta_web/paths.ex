defmodule AmautaWeb.Paths do
  @moduledoc """
  Constructor único de URLs consciente de la institución (ERS 8.4).
  Nunca se arma una URL a mano. Por ahora solo el modo ruta
  (`/<institución>/…`); los modos por host se agregan acá.
  """
  use AmautaWeb, :verified_routes

  alias Amauta.Platform.Institution

  def course_feed(tenant, course), do: ~p"/#{slug(tenant)}/c/#{course.slug}/feed"

  def dev_login(tenant, user, to), do: ~p"/#{slug(tenant)}/dev/login/#{user.id}?#{[to: to]}"

  defp slug(%Institution{slug: slug}), do: slug
  defp slug(%{institution: %Institution{slug: slug}}), do: slug
end
