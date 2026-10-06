defmodule Amauta.Platform do
  @moduledoc "Instancia y registro de instituciones."
  import Ecto.Query
  alias Amauta.Platform.Institution
  alias Amauta.Repo

  def get_institution_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Institution, slug: slug)
  end

  def get_institution!(id), do: Repo.get!(Institution, id)

  def list_institutions do
    Repo.all(from(i in Institution, order_by: i.name))
  end

  def update_institution(%Institution{} = institution, attrs) do
    institution |> Institution.changeset(attrs) |> Repo.update()
  end

  def suspend_institution(%Institution{} = institution) do
    institution |> Institution.status_changeset("suspended") |> Repo.update()
  end

  def activate_institution(%Institution{} = institution) do
    institution |> Institution.status_changeset("active") |> Repo.update()
  end
end
