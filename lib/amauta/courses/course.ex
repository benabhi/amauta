defmodule Amauta.Courses.Course do
  @moduledoc """
  Curso (RF-CUR-001): la unidad mínima de cursado, con tablón, contenido,
  personas y calificaciones. Puede estar suelto en la institución o
  pertenecer a un trayecto propietario (reglas R2 y R3), en una de sus
  etapas y como obligatorio u optativo (RF-TRA-002).

  Estados (ERS 4.8): `draft` → `published` → `archived`, y un archivado se
  puede reabrir. La papelera y el archivado en frío llegan en V1.

  La portada es generativa (`AmautaWeb.CoreComponents.cover/1`): sale del
  ID, el ícono y el color, sin guardar imágenes.
  """
  use Amauta.Schema

  alias Amauta.Courses.Settings
  alias Amauta.Pathways.{Pathway, Stage}
  alias Amauta.Periods.AcademicPeriod

  @type t :: %__MODULE__{}

  @statuses ~w(draft published archived)
  @colors ~w(anil airampo chilca qolle cochinilla nogal)

  # Íconos de Phosphor que se pueden elegir para un curso.
  @icons ~w(book-open code calculator flask globe-hemisphere-west palette music-notes
            translate chart-line scales heartbeat leaf)

  schema "courses" do
    field :name, :string
    field :code, :string
    field :slug, :string
    field :description, :string
    field :icon, :string, default: "book-open"
    field :color, :string, default: "anil"
    field :status, :string, default: "draft"
    field :archived_at, :utc_datetime_usec
    field :required, :boolean, default: true
    field :enrollment_code, :string

    belongs_to :period, AcademicPeriod
    belongs_to :pathway, Pathway
    belongs_to :stage, Stage
    embeds_one :settings, Settings, on_replace: :update, defaults_to_struct: true

    timestamps()
  end

  def statuses, do: @statuses
  def colors, do: @colors
  def icons, do: @icons

  @doc "Datos del curso. El trayecto y la etapa se validan en `Amauta.Courses`."
  def changeset(course, attrs) do
    course
    |> cast(attrs, [
      :name,
      :code,
      :slug,
      :description,
      :icon,
      :color,
      :period_id,
      :pathway_id,
      :stage_id,
      :required
    ])
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
    |> validate_inclusion(:icon, @icons)
    |> validate_inclusion(:color, @colors)
    |> clear_stage_without_pathway()
    |> unique_constraint(:slug, message: "already in use")
    |> foreign_key_constraint(:period_id)
    |> foreign_key_constraint(:pathway_id)
    |> foreign_key_constraint(:stage_id)
  end

  @doc "Ajustes del curso (RF-CUR-007)."
  def settings_changeset(course, attrs) do
    course
    |> cast(attrs, [])
    |> cast_embed(:settings)
  end

  def status_changeset(course, status) when status in @statuses do
    archived_at = if status == "archived", do: DateTime.utc_now()
    change(course, status: status, archived_at: archived_at)
  end

  defp clear_stage_without_pathway(changeset) do
    if get_field(changeset, :pathway_id),
      do: changeset,
      else: put_change(changeset, :stage_id, nil)
  end

  defimpl Amauta.Authorization.Target do
    def scope_chain(%{id: id, pathway_id: nil}), do: [{"course", id}]

    def scope_chain(%{id: id, pathway_id: pathway_id}),
      do: [{"course", id}, {"pathway", pathway_id}]
  end
end
