defmodule Amauta.Platform.Institution do
  @moduledoc "Institución registrada en el schema global (ERS 4.11)."
  use Amauta.Schema

  @type t :: %__MODULE__{}

  @statuses ~w(active suspended)
  @reserved_slugs ~w(admin api assets dev fonts health images live login logout phoenix setup storybook)

  @schema_prefix "global"
  schema "institutions" do
    field :slug, :string
    field :name, :string
    field :short_name, :string
    field :schema_name, :string
    field :status, :string, default: "active"
    field :timezone, :string, default: "America/Argentina/Buenos_Aires"
    field :locale, :string, default: "es"
    field :terminology_preset, :string, default: "generic"
    field :terminology, :map, default: %{}
    field :schema_version, :integer
    field :migration_error, :string
    field :migrated_at, :utc_datetime_usec

    timestamps()
  end

  def reserved_slugs, do: @reserved_slugs

  @doc "Alta: el schema se asigna una sola vez y no depende del slug."
  def create_changeset(institution, attrs) do
    institution
    |> changeset(attrs)
    |> put_change(:schema_name, generate_schema_name())
    |> unique_constraint(:schema_name)
  end

  def changeset(institution, attrs) do
    institution
    |> cast(attrs, [
      :slug,
      :name,
      :short_name,
      :timezone,
      :locale,
      :terminology_preset,
      :terminology
    ])
    |> update_change(:slug, &String.downcase/1)
    |> validate_required([:slug, :name])
    |> validate_length(:slug, min: 2, max: 63)
    |> validate_format(:slug, ~r/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/)
    |> validate_exclusion(:slug, @reserved_slugs)
    |> validate_length(:name, max: 200)
    |> validate_length(:short_name, max: 50)
    |> validate_inclusion(:timezone, Tzdata.zone_list())
    |> validate_inclusion(:locale, Amauta.Locale.supported())
    |> validate_inclusion(:terminology_preset, Amauta.Terminology.presets())
    |> validate_change(:terminology, fn :terminology, overrides ->
      case Amauta.Terminology.validate_overrides(overrides) do
        :ok -> []
        {:error, _reason} -> [terminology: "is invalid"]
      end
    end)
    |> unique_constraint(:slug)
  end

  def status_changeset(institution, status) do
    institution |> change(status: status) |> validate_inclusion(:status, @statuses)
  end

  @doc "Resultado del último intento de migración del schema (RF-ADM-006)."
  def migration_changeset(institution, attrs) do
    cast(institution, attrs, [:schema_version, :migration_error, :migrated_at])
  end

  # Nombre estable e independiente del slug (ERS 8.3): `inst_` + 10 caracteres.
  defp generate_schema_name do
    "inst_" <> (:crypto.strong_rand_bytes(6) |> Base.encode32(case: :lower, padding: false))
  end
end
