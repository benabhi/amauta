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
  def periods(tenant), do: ~p"/#{slug(tenant)}/periods"
  def new_period(tenant), do: ~p"/#{slug(tenant)}/periods/new"
  def edit_period(tenant, period), do: ~p"/#{slug(tenant)}/periods/#{period.id}/edit"
  def pathways(tenant), do: ~p"/#{slug(tenant)}/pathways"
  def pathways(tenant, params), do: ~p"/#{slug(tenant)}/pathways?#{params}"
  def new_pathway(tenant), do: ~p"/#{slug(tenant)}/pathways/new"
  def pathway(tenant, pathway), do: ~p"/#{slug(tenant)}/pathways/#{pathway.slug}"
  def edit_pathway(tenant, pathway), do: ~p"/#{slug(tenant)}/pathways/#{pathway.slug}/edit"
  def courses(tenant), do: ~p"/#{slug(tenant)}/courses"
  def courses(tenant, params), do: ~p"/#{slug(tenant)}/courses?#{params}"
  def new_course(tenant), do: ~p"/#{slug(tenant)}/courses/new"
  def new_course(tenant, params), do: ~p"/#{slug(tenant)}/courses/new?#{params}"

  @doc "Pestaña de un curso: `:feed` (por defecto), `:content`, `:people`, `:grades` o `:settings`."
  def course(tenant, course, tab \\ :feed)
  def course(tenant, course, :feed), do: ~p"/#{slug(tenant)}/c/#{course.slug}"
  def course(tenant, course, :content), do: ~p"/#{slug(tenant)}/c/#{course.slug}/content"
  def course(tenant, course, :people), do: ~p"/#{slug(tenant)}/c/#{course.slug}/people"
  def course(tenant, course, :grades), do: ~p"/#{slug(tenant)}/c/#{course.slug}/grades"
  def course(tenant, course, :settings), do: ~p"/#{slug(tenant)}/c/#{course.slug}/settings"

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
