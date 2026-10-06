defmodule Amauta.Platform.Institution do
  @moduledoc "Institución registrada en el schema global."
  use Amauta.Schema

  @schema_prefix "global"
  schema "institutions" do
    field :slug, :string
    field :name, :string
    field :schema_name, :string

    timestamps()
  end

  @reserved_slugs ~w(api admin assets live health login dev)

  def changeset(institution, attrs) do
    institution
    |> cast(attrs, [:slug, :name, :schema_name])
    |> validate_required([:slug, :name, :schema_name])
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]*$/)
    |> validate_exclusion(:slug, @reserved_slugs)
    |> validate_format(:schema_name, ~r/^inst_[a-z0-9_]+$/)
    |> unique_constraint(:slug)
    |> unique_constraint(:schema_name)
  end
end
