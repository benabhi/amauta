defmodule Amauta.Courses.Section do
  @moduledoc """
  Comisión de un curso (RF-COM-001): una subdivisión con sus docentes, su
  horario y su aula, por ejemplo «Comisión A · Mañana». Cada estudiante
  pertenece a una (`Amauta.Enrollments.Enrollment.section_id`).

  Como objetivo de permisos, su cadena es comisión › curso › trayecto: hay
  que tenerla con el curso precargado.
  """
  use Amauta.Schema

  alias Amauta.Courses.Course

  @type t :: %__MODULE__{}

  schema "course_sections" do
    field :name, :string
    field :schedule, :string
    field :room, :string
    belongs_to :course, Course

    timestamps()
  end

  def changeset(section, attrs) do
    section
    |> cast(attrs, [:name, :schedule, :room])
    |> update_change(:name, &trim/1)
    |> update_change(:schedule, &trim/1)
    |> update_change(:room, &trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> validate_length(:schedule, max: 120)
    |> validate_length(:room, max: 80)
    |> unique_constraint(:name, name: :course_sections_name_index, message: "already exists")
  end

  defimpl Amauta.Authorization.Target do
    def scope_chain(%{id: id, course: %Course{} = course}),
      do: [{"section", id} | Amauta.Authorization.Target.scope_chain(course)]
  end
end
