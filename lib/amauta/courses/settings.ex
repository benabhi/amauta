defmodule Amauta.Courses.Settings do
  @moduledoc """
  Ajustes mínimos y opinados de un curso (RF-CUR-007). Cada uno tiene un
  valor por defecto razonable: un curso recién creado funciona sin tocar
  nada. Las comisiones se gestionan aparte; la asistencia llega en V1.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @visibilities ~w(participants institution)
  @feed_posting ~w(teachers everyone moderated)
  @grading_scales ~w(numeric percentage pass_fail)
  @unit_names ~w(unit week class module)

  @primary_key false
  embedded_schema do
    # participants: solo quienes están matriculados; institution: además,
    # cualquier persona de la institución puede ver su ficha.
    field :visibility, :string, default: "participants"
    field :enrollment_code_enabled, :boolean, default: false
    field :feed_posting, :string, default: "teachers"
    field :comments_enabled, :boolean, default: true
    field :grading_scale, :string, default: "numeric"
    field :unit_name, :string, default: "unit"
  end

  def visibilities, do: @visibilities
  def feed_posting_options, do: @feed_posting
  def grading_scales, do: @grading_scales
  def unit_names, do: @unit_names

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [
      :visibility,
      :enrollment_code_enabled,
      :feed_posting,
      :comments_enabled,
      :grading_scale,
      :unit_name
    ])
    |> validate_inclusion(:visibility, @visibilities)
    |> validate_inclusion(:feed_posting, @feed_posting)
    |> validate_inclusion(:grading_scale, @grading_scales)
    |> validate_inclusion(:unit_name, @unit_names)
  end
end
