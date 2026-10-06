defmodule Amauta.Catalog.Course do
  @moduledoc "Curso de una institución."
  use Amauta.Schema

  schema "courses" do
    field :slug, :string
    field :name, :string

    timestamps()
  end

  def changeset(course, attrs) do
    course
    |> cast(attrs, [:slug, :name])
    |> validate_required([:slug, :name])
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]*$/)
    |> unique_constraint(:slug)
  end
end
