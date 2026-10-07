defmodule Amauta.Content.Unit do
  @moduledoc """
  Unidad del contenido de un curso (RF-CON-001): agrupa elementos, con
  título, descripción, fechas opcionales y visibilidad. Las unidades del
  curso se ordenan a mano (`position`).

  Visibilidad: `visible`, `hidden` (solo el equipo docente) o `scheduled`
  (se ve desde `publish_at`).
  """
  use Amauta.Schema

  alias Amauta.Content.Item
  alias Amauta.Courses.Course

  @type t :: %__MODULE__{}

  @visibilities ~w(visible hidden scheduled)

  schema "course_units" do
    field :title, :string
    field :description, :string
    field :starts_on, :date
    field :ends_on, :date
    field :visibility, :string, default: "visible"
    field :publish_at, :utc_datetime_usec
    field :position, :integer, default: 0

    belongs_to :course, Course
    has_many :items, Item, preload_order: [asc: :position]

    timestamps()
  end

  @doc "Visibilidades posibles."
  def visibilities, do: @visibilities

  def changeset(unit, attrs) do
    unit
    |> cast(attrs, [:title, :description, :starts_on, :ends_on, :visibility, :publish_at])
    |> update_change(:title, &trim/1)
    |> update_change(:description, &trim/1)
    |> validate_required([:title])
    |> validate_length(:title, max: 160)
    |> validate_length(:description, max: 2000)
    |> Amauta.Content.validate_visibility()
    |> validate_dates()
  end

  defp validate_dates(changeset) do
    starts_on = get_field(changeset, :starts_on)
    ends_on = get_field(changeset, :ends_on)

    if starts_on && ends_on && Date.after?(starts_on, ends_on),
      do: add_error(changeset, :ends_on, "must be after the start date"),
      else: changeset
  end
end
