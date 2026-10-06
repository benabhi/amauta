defmodule Amauta.Pathways.Pathway do
  @moduledoc """
  Trayecto (RF-TRA-001): agrupa cursos en etapas ordenadas, como una
  carrera o un programa. Es opcional (regla R2): un curso puede existir
  suelto en la institución.

  Estados (ERS 4.8): `draft` → `published` → `archived`, y un archivado se
  puede reabrir. La papelera, el archivado en frío, la portada, la
  categoría, las etiquetas y los campos personalizados llegan en V1.
  """
  use Amauta.Schema

  alias Amauta.Pathways.Stage

  @type t :: %__MODULE__{}

  @statuses ~w(draft published archived)

  schema "pathways" do
    field :name, :string
    field :code, :string
    field :slug, :string
    field :description, :string
    field :status, :string, default: "draft"
    field :archived_at, :utc_datetime_usec

    has_many :stages, Stage, preload_order: [asc: :position]

    timestamps()
  end

  def statuses, do: @statuses

  def changeset(pathway, attrs) do
    pathway
    |> cast(attrs, [:name, :code, :slug, :description])
    |> update_change(:name, &trim/1)
    |> update_change(:code, &trim/1)
    |> update_change(:slug, &(&1 && &1 |> String.trim() |> String.downcase()))
    |> validate_required([:name, :slug])
    |> validate_length(:name, max: 160)
    |> validate_length(:code, max: 40)
    |> validate_length(:slug, min: 1, max: 63)
    |> validate_format(:slug, Amauta.Slug.format(),
      message: "only lowercase letters, digits and hyphens"
    )
    |> validate_exclusion(:slug, ~w(new), message: "is reserved")
    |> validate_length(:description, max: 5000)
    |> unique_constraint(:slug, message: "already in use")
    |> unique_constraint(:code, message: "already in use")
  end

  def status_changeset(pathway, status) when status in @statuses do
    archived_at = if status == "archived", do: DateTime.utc_now()
    change(pathway, status: status, archived_at: archived_at)
  end

  defimpl Amauta.Authorization.Target do
    def scope_chain(%{id: id}), do: [{"pathway", id}]
  end
end
