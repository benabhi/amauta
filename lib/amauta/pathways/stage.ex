defmodule Amauta.Pathways.Stage do
  @moduledoc """
  Etapa de un trayecto (RF-TRA-002), por ejemplo «1.er año». Las etapas
  están ordenadas por `position`, desde 1. Los cursos de cada etapa
  (obligatorios u optativos) llegan con los cursos.
  """
  use Amauta.Schema

  @type t :: %__MODULE__{}

  schema "pathway_stages" do
    field :name, :string
    field :position, :integer
    belongs_to :pathway, Amauta.Pathways.Pathway

    timestamps()
  end

  def changeset(stage, attrs) do
    stage
    |> cast(attrs, [:name])
    |> update_change(:name, &trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 120)
  end
end
