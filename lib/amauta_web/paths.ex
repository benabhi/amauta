defmodule AmautaWeb.Paths do
  @moduledoc """
  Constructor único de URLs consciente de la institución (ERS 8.4 y
  RF-ADM-008). Nunca se arma una URL de institución a mano: se pide acá.

  Por ahora solo existe el modo ruta (`/<institución>/…`). Los modos
  subdominio, institución única y dominio propio se agregan en este módulo
  sin tocar a quienes lo usan.

  Cada función recibe un «tenant»: la institución o un `Amauta.Scope`.
  """
  use AmautaWeb, :verified_routes

  alias Amauta.Platform.Institution

  def home(tenant), do: ~p"/#{slug(tenant)}"
  def log_in(tenant), do: ~p"/#{slug(tenant)}/log-in"
  def log_in(tenant, token), do: ~p"/#{slug(tenant)}/log-in/#{token}"
  def log_out(tenant), do: ~p"/#{slug(tenant)}/log-out"
  def settings(tenant), do: ~p"/#{slug(tenant)}/settings"
  def confirm_email(tenant, token), do: ~p"/#{slug(tenant)}/settings/confirm-email/#{token}"
  def update_password(tenant), do: ~p"/#{slug(tenant)}/update-password"

  @doc "URL absoluta, para emails y enlaces que salen de la plataforma."
  def absolute(path) when is_binary(path), do: AmautaWeb.Endpoint.url() <> path

  defp slug(%Institution{slug: slug}), do: slug
  defp slug(%{institution: %Institution{slug: slug}}), do: slug
end
