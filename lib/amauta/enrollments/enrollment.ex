defmodule Amauta.Enrollments.Enrollment do
  @moduledoc """
  Matrícula de una persona en un curso (RF-MAT-002): rol, estado, fechas,
  comisión y origen. Hay una por persona y curso; cambiar el rol o la
  comisión la actualiza, y dar de baja la deja finalizada sin borrar nada
  (RF-MAT-003).

  Estados: `active`, `pending` (por ejemplo, esperando aprobación, V1),
  `suspended` y `ended`. Orígenes: `manual`, `csv`, `pathway` y `code`.
  """
  use Amauta.Schema

  alias Amauta.Accounts.User
  alias Amauta.Courses.{Course, Section}

  @type t :: %__MODULE__{}

  @roles ~w(course_lead teacher assistant student observer)
  @teaching_roles ~w(course_lead teacher assistant)
  @statuses ~w(active pending suspended ended)
  @origins ~w(manual csv pathway code)

  schema "enrollments" do
    field :role, :string
    field :status, :string, default: "active"
    field :origin, :string
    field :starts_on, :date
    field :ends_on, :date
    field :ended_at, :utc_datetime_usec
    field :enrolled_by_id, Ecto.UUID

    belongs_to :course, Course
    belongs_to :user, User
    belongs_to :section, Section

    timestamps()
  end

  def roles, do: @roles
  def teaching_roles, do: @teaching_roles
  def statuses, do: @statuses
  def origins, do: @origins

  def changeset(enrollment, attrs) do
    enrollment
    |> cast(attrs, [:role, :status, :origin, :section_id, :starts_on, :ends_on, :enrolled_by_id])
    |> validate_required([:role, :status, :origin])
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:origin, @origins)
    |> validate_dates()
    |> put_ended_at()
    |> unique_constraint([:course_id, :user_id],
      name: :enrollments_course_id_user_id_index,
      message: "already enrolled"
    )
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:section_id)
  end

  defp validate_dates(changeset) do
    starts_on = get_field(changeset, :starts_on)
    ends_on = get_field(changeset, :ends_on)

    if starts_on && ends_on && Date.before?(ends_on, starts_on),
      do: add_error(changeset, :ends_on, "must be after the start"),
      else: changeset
  end

  defp put_ended_at(changeset) do
    case get_change(changeset, :status) do
      "ended" -> put_change(changeset, :ended_at, DateTime.utc_now())
      nil -> changeset
      _other -> put_change(changeset, :ended_at, nil)
    end
  end
end
