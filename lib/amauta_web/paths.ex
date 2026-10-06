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
  def people(tenant), do: ~p"/#{slug(tenant)}/people"
  def people(tenant, params), do: ~p"/#{slug(tenant)}/people?#{params}"
  def new_person(tenant), do: ~p"/#{slug(tenant)}/people/new"
  def edit_person(tenant, user), do: ~p"/#{slug(tenant)}/people/#{user.id}/edit"
  def import_people(tenant), do: ~p"/#{slug(tenant)}/people/import"
  def export_people(tenant, params), do: ~p"/#{slug(tenant)}/people/export?#{params}"

  @doc """
  Inicio de sesión rápido de desarrollo (RNF-DEV-009). Sin rutas
  verificadas: la ruta solo existe con `config :amauta, dev_login: true`.
  """
  def dev_login(tenant), do: "/#{slug(tenant)}/dev/login"
  def dev_login(tenant, user), do: "/#{slug(tenant)}/dev/login/#{user.id}"

  @doc "URL absoluta del enlace mágico (la usa el dominio para las invitaciones)."
  def absolute_log_in(tenant, token), do: absolute(log_in(tenant, token))

  @doc "URL absoluta, para emails y enlaces que salen de la plataforma."
  def absolute(path) when is_binary(path), do: AmautaWeb.Endpoint.url() <> path

  defp slug(%Institution{slug: slug}), do: slug
  defp slug(%{institution: %Institution{slug: slug}}), do: slug
end
