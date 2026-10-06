defmodule Amauta.Enrollments.Actions.Helpers do
  @moduledoc false
  alias Amauta.{Authorization, Courses, Enrollments}

  def fetch_course(scope, id) do
    case Courses.get(scope, id) do
      nil -> {:error, :not_found}
      %{status: "archived"} -> {:error, :archived}
      course -> {:ok, course}
    end
  end

  def fetch_section(scope, id) do
    case Enrollments.get_section(scope, id) do
      nil -> {:error, :not_found}
      %{course: %{status: "archived"}} -> {:error, :archived}
      section -> {:ok, section}
    end
  end

  def fetch_enrollment(scope, id) do
    case Enrollments.get(scope, id) do
      nil -> {:error, :not_found}
      %{course: %{status: "archived"}} -> {:error, :archived}
      enrollment -> {:ok, enrollment}
    end
  end

  @doc """
  Para matricular con un rol: el permiso de matricular en el curso (o en
  la comisión) y, por anti-escalada (RF-ROL-005), poder dar ese rol ahí.
  """
  def authorize_enroll(scope, course, section_id, role) do
    target =
      case section_id && Enrollments.get_section(scope, section_id) do
        %{course_id: course_id} = section when course_id == course.id ->
          %{section | course: course}

        _ ->
          course
      end

    with :ok <- Authorization.authorize(scope, "course.people.enroll", target) do
      if Authorization.can_grant?(scope, role, target), do: :ok, else: {:error, :forbidden}
    end
  end
end

defmodule Amauta.Enrollments.Actions.CreateSection do
  @moduledoc "Crea una comisión en un curso (RF-COM-001)."
  use Amauta.Action,
    name: "enrollments.section.create",
    description: "Crea una comisión.",
    params: [
      course_id: {Ecto.UUID, required: true},
      name: {:string, required: true},
      schedule: :string,
      room: :string
    ]

  alias Amauta.{Authorization, Courses, Enrollments}
  alias Amauta.Enrollments.Actions.Helpers

  @impl true
  def authorize(scope, %{course_id: id}) do
    case Courses.get(scope, id) do
      nil -> {:error, :not_found}
      course -> Authorization.authorize(scope, "course.sections.manage", course)
    end
  end

  @impl true
  def run(scope, %{course_id: id} = input) do
    with {:ok, course} <- Helpers.fetch_course(scope, id) do
      Enrollments.create_section(scope, course, Map.delete(input, :course_id))
    end
  end
end

defmodule Amauta.Enrollments.Actions.UpdateSection do
  @moduledoc "Edita el nombre, el horario o el aula de una comisión."
  use Amauta.Action,
    name: "enrollments.section.update",
    description: "Edita una comisión.",
    params: [
      section_id: {Ecto.UUID, required: true},
      name: :string,
      schedule: :string,
      room: :string
    ]

  alias Amauta.Courses.Section
  alias Amauta.Enrollments.Actions.Helpers
  alias Amauta.{Authorization, Enrollments, Repo, Tenancy}

  @impl true
  def authorize(scope, %{section_id: id}) do
    case Enrollments.get_section(scope, id) do
      nil -> {:error, :not_found}
      section -> Authorization.authorize(scope, "course.sections.manage", section.course)
    end
  end

  @impl true
  def run(scope, %{section_id: id} = input) do
    with {:ok, section} <- Helpers.fetch_section(scope, id) do
      section
      |> Section.changeset(Map.delete(input, :section_id))
      |> Repo.update(Tenancy.opts(scope))
    end
  end
end

defmodule Amauta.Enrollments.Actions.DeleteSection do
  @moduledoc """
  Borra una comisión. Sus estudiantes quedan sin comisión y su equipo
  docente pasa al curso entero; nadie pierde la matrícula.
  """
  use Amauta.Action,
    name: "enrollments.section.delete",
    description: "Borra una comisión.",
    params: [section_id: {Ecto.UUID, required: true}]

  alias Amauta.Enrollments.Actions.Helpers
  alias Amauta.{Authorization, Enrollments}

  @impl true
  def authorize(scope, %{section_id: id}) do
    case Enrollments.get_section(scope, id) do
      nil -> {:error, :not_found}
      section -> Authorization.authorize(scope, "course.sections.manage", section.course)
    end
  end

  @impl true
  def run(scope, %{section_id: id}) do
    with {:ok, section} <- Helpers.fetch_section(scope, id) do
      Enrollments.delete_section(scope, section)
    end
  end
end

defmodule Amauta.Enrollments.Actions.EnrollUser do
  @moduledoc "Matricula a una persona en un curso, a mano (RF-MAT-001)."
  use Amauta.Action,
    name: "enrollments.enrollment.create",
    description: "Matricula a una persona en un curso.",
    params: [
      course_id: {Ecto.UUID, required: true},
      user_id: {Ecto.UUID, required: true},
      role: {:string, required: true},
      section_id: Ecto.UUID
    ]

  import Ecto.Changeset

  alias Amauta.Enrollments
  alias Amauta.Enrollments.Actions.Helpers
  alias Amauta.Enrollments.Enrollment

  @impl true
  def validate(changeset), do: validate_inclusion(changeset, :role, Enrollment.roles())

  @impl true
  def authorize(scope, %{course_id: id, role: role} = input) do
    case Amauta.Courses.get(scope, id) do
      nil -> {:error, :not_found}
      course -> Helpers.authorize_enroll(scope, course, input[:section_id], role)
    end
  end

  @impl true
  def run(scope, %{course_id: id, user_id: user_id} = input) do
    with {:ok, course} <- Helpers.fetch_course(scope, id) do
      Enrollments.enroll(scope, course, user_id, %{
        role: input.role,
        section_id: input[:section_id],
        origin: "manual",
        enrolled_by_id: scope.user.id
      })
    end
  end
end

defmodule Amauta.Enrollments.Actions.UpdateEnrollment do
  @moduledoc """
  Cambia el rol, la comisión o el estado (activa o suspendida) de una
  matrícula. Exige poder matricular con el rol nuevo en la comisión nueva.
  """
  use Amauta.Action,
    name: "enrollments.enrollment.update",
    description: "Cambia el rol, la comisión o el estado de una matrícula.",
    params: [
      enrollment_id: {Ecto.UUID, required: true},
      role: :string,
      section_id: Ecto.UUID,
      status: :string
    ]

  import Ecto.Changeset

  alias Amauta.Enrollments
  alias Amauta.Enrollments.Actions.Helpers
  alias Amauta.Enrollments.Enrollment

  @impl true
  def validate(changeset) do
    changeset
    |> validate_inclusion(:role, Enrollment.roles())
    |> validate_inclusion(:status, ~w(active suspended))
  end

  @impl true
  def authorize(scope, %{enrollment_id: id} = input) do
    case Enrollments.get(scope, id) do
      nil ->
        {:error, :not_found}

      enrollment ->
        section_id = Map.get(input, :section_id, enrollment.section_id)
        role = input[:role] || enrollment.role

        # Hay que poder gestionar la matrícula como está y como queda.
        with :ok <-
               Helpers.authorize_enroll(
                 scope,
                 enrollment.course,
                 enrollment.section_id,
                 enrollment.role
               ) do
          Helpers.authorize_enroll(scope, enrollment.course, section_id, role)
        end
    end
  end

  @impl true
  def run(scope, %{enrollment_id: id} = input) do
    with {:ok, enrollment} <- Helpers.fetch_enrollment(scope, id) do
      Enrollments.update(scope, enrollment, Map.delete(input, :enrollment_id))
    end
  end
end

defmodule Amauta.Enrollments.Actions.EndEnrollment do
  @moduledoc """
  Da de baja una matrícula: queda finalizada y la persona pierde el acceso,
  pero su historial (entregas y notas) se conserva (RF-MAT-003).
  """
  use Amauta.Action,
    name: "enrollments.enrollment.end",
    description: "Da de baja una matrícula conservando el historial.",
    params: [enrollment_id: {Ecto.UUID, required: true}]

  alias Amauta.Enrollments
  alias Amauta.Enrollments.Actions.Helpers

  @impl true
  def authorize(scope, %{enrollment_id: id}) do
    case Enrollments.get(scope, id) do
      nil ->
        {:error, :not_found}

      e ->
        Helpers.authorize_enroll(scope, e.course, e.section_id, e.role)
    end
  end

  @impl true
  def run(scope, %{enrollment_id: id}) do
    with {:ok, enrollment} <- Helpers.fetch_enrollment(scope, id) do
      Enrollments.update(scope, enrollment, %{status: "ended"})
    end
  end
end

defmodule Amauta.Enrollments.Actions.ImportEnrollments do
  @moduledoc """
  Matricula a varias personas desde un CSV ya validado (RF-MAT-001). Cada
  fila trae la persona, el rol y la comisión; la validación y la simulación
  están en `Amauta.Enrollments.Import`. Todo o nada.
  """
  use Amauta.Action,
    name: "enrollments.enrollment.import",
    description: "Matricula personas desde un CSV.",
    params: [
      course_id: {Ecto.UUID, required: true},
      rows: {{:array, :map}, required: true}
    ]

  alias Amauta.Enrollments
  alias Amauta.Enrollments.Actions.Helpers

  @impl true
  def authorize(scope, %{course_id: id, rows: rows}) do
    case Amauta.Courses.get(scope, id) do
      nil ->
        {:error, :not_found}

      course ->
        rows
        |> Enum.map(&{&1["section_id"], &1["role"] || "student"})
        |> Enum.uniq()
        |> Enum.reduce_while(:ok, fn {section_id, role}, :ok ->
          case Helpers.authorize_enroll(scope, course, section_id, role) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        end)
    end
  end

  @impl true
  def run(scope, %{course_id: id, rows: rows}) do
    with {:ok, course} <- Helpers.fetch_course(scope, id) do
      Enrollments.enroll_many(scope, course, rows, "csv", scope.user.id)
    end
  end

  @impl true
  def audit(_scope, %{course_id: id, rows: rows}, result),
    do: {nil, %{course_id: id, rows: length(rows), result: result}}
end

defmodule Amauta.Enrollments.Actions.EnrollInPathway do
  @moduledoc """
  Matricula estudiantes en los cursos de un trayecto (RF-TRA-003): en
  todos, solo en los obligatorios o en los de una etapa. Los cursos
  archivados no cuentan. La comisión se asigna después, en cada curso.
  """
  use Amauta.Action,
    name: "enrollments.pathway.enroll",
    description: "Matricula estudiantes en los cursos de un trayecto.",
    params: [
      pathway_id: {Ecto.UUID, required: true},
      user_ids: {{:array, Ecto.UUID}, required: true},
      propagation: {:string, required: true},
      stage_id: Ecto.UUID
    ]

  import Ecto.Changeset
  import Ecto.Query

  alias Amauta.Courses.Course
  alias Amauta.{Authorization, Enrollments, Pathways, Repo, Tenancy}

  @impl true
  def validate(changeset) do
    changeset
    |> validate_inclusion(:propagation, ~w(all required stage))
    |> validate_length(:user_ids, min: 1)
    |> then(fn cs ->
      if get_field(cs, :propagation) == "stage", do: validate_required(cs, [:stage_id]), else: cs
    end)
  end

  @impl true
  def authorize(scope, %{pathway_id: id}) do
    case Pathways.get(scope, id) do
      nil ->
        {:error, :not_found}

      pathway ->
        with :ok <- Authorization.authorize(scope, "pathway.enrollments.manage", pathway) do
          if Authorization.can_grant?(scope, "student", pathway),
            do: :ok,
            else: {:error, :forbidden}
        end
    end
  end

  @impl true
  def run(scope, %{pathway_id: id, user_ids: user_ids} = input) do
    case Pathways.get(scope, id) do
      %{status: "archived"} ->
        {:error, :archived}

      pathway ->
        courses =
          from(c in Course, where: c.pathway_id == ^pathway.id and c.status != "archived")
          |> propagation(input)
          |> Repo.all(Tenancy.opts(scope))

        rows = for user_id <- user_ids, do: %{"user_id" => user_id, "role" => "student"}

        Enum.reduce_while(courses, {:ok, %{courses: length(courses), enrolled: 0, skipped: 0}}, fn
          course, {:ok, acc} ->
            case Enrollments.enroll_many(scope, course, rows, "pathway", scope.user.id) do
              {:ok, %{enrolled: e, skipped: s}} ->
                {:cont, {:ok, %{acc | enrolled: acc.enrolled + e, skipped: acc.skipped + s}}}

              error ->
                {:halt, error}
            end
        end)
    end
  end

  defp propagation(query, %{propagation: "required"}), do: where(query, [c], c.required)

  defp propagation(query, %{propagation: "stage", stage_id: stage_id}),
    do: where(query, [c], c.stage_id == ^stage_id)

  defp propagation(query, _input), do: query

  @impl true
  def audit(_scope, %{pathway_id: id} = input, result) do
    {nil,
     %{
       pathway_id: id,
       people: length(input.user_ids),
       propagation: input.propagation,
       result: result
     }}
  end
end

defmodule Amauta.Enrollments.Actions.JoinWithCode do
  @moduledoc """
  La persona se suma a un curso como estudiante con su código de
  inscripción (RF-MAT-001), si el curso está publicado y lo permite.
  """
  use Amauta.Action,
    name: "enrollments.enrollment.join",
    description: "Se suma a un curso con el código de inscripción.",
    params: [code: {:string, required: true}]

  alias Amauta.Enrollments

  @impl true
  def authorize(%{user: nil}, _input), do: {:error, :forbidden}
  def authorize(_scope, _input), do: :ok

  @impl true
  def run(scope, %{code: code}) do
    case Enrollments.course_for_code(scope, code) do
      nil ->
        {:error, :invalid_code}

      course ->
        case Enrollments.get_by_user(scope, course, scope.user.id) do
          %{status: "active"} ->
            {:ok, course}

          # Una suspensión la levanta el equipo docente, no el código.
          %{status: "suspended"} ->
            {:error, :suspended}

          _ ->
            with {:ok, _enrollment} <-
                   Enrollments.enroll(scope, course, scope.user.id, %{
                     role: "student",
                     origin: "code",
                     enrolled_by_id: scope.user.id
                   }),
                 do: {:ok, course}
        end
    end
  end
end
