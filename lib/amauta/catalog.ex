defmodule Amauta.Catalog do
  @moduledoc "Cursos. Toda función recibe la institución."
  alias Amauta.Catalog.Course
  alias Amauta.{Repo, Tenancy}

  def create_course(tenant, attrs) do
    %Course{} |> Course.changeset(attrs) |> Repo.insert(Tenancy.opts(tenant))
  end

  def get_course(tenant, id) do
    with {:ok, id} <- Ecto.UUID.cast(id), do: Repo.get(Course, id, Tenancy.opts(tenant))
  end

  def get_course_by_slug(tenant, slug),
    do: Repo.get_by(Course, [slug: slug], Tenancy.opts(tenant))
end
