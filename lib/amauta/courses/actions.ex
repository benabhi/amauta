defmodule Amauta.Courses.Actions.Helpers do
  @moduledoc false
  alias Amauta.Courses.Course
  alias Amauta.{Authorization, Courses, Pathways, Repo, Tenancy}

  @doc "Verifica el permiso sobre el curso; si no existe, `:not_found`."
  def authorize_course(scope, id, permission) do
    case Courses.get(scope, id) do
      nil -> {:error, :not_found}
      course -> Authorization.authorize(scope, permission, course)
    end
  end

  @doc """
  Verifica el permiso para crear o mover un curso dentro de un trayecto
  (o suelto en la institución, si no hay trayecto).
  """
  def authorize_in_pathway(scope, nil, permission),
    do: Authorization.authorize(scope, permission)

  def authorize_in_pathway(scope, pathway_id, permission) do
    case Pathways.get(scope, pathway_id) do
      nil -> {:error, :not_found}
      pathway -> Authorization.authorize(scope, permission, pathway)
    end
  end

  def fetch_course(scope, id) do
    case Courses.get(scope, id) do
      nil -> {:error, :not_found}
      course -> {:ok, course}
    end
  end

  @doc "Curso que se puede modificar: uno archivado es de solo lectura."
  def fetch_editable_course(scope, id) do
    case fetch_course(scope, id) do
      {:ok, %{status: "archived"}} -> {:error, :archived}
      result -> result
    end
  end

  @doc "Cambia el estado si la transición es válida (ERS 4.8)."
  def transition(scope, id, from, to) do
    with {:ok, course} <- fetch_course(scope, id) do
      if course.status in from do
        course |> Course.status_changeset(to) |> Repo.update(Tenancy.opts(scope))
      else
        {:error, :invalid_transition}
      end
    end
  end
end

defmodule Amauta.Courses.Actions.CreateCourse do
  @moduledoc """
  Crea un curso en borrador (RF-CUR-001), suelto o dentro de un trayecto.
  Exige `institution.courses.create` en la institución o en el trayecto:
  la coordinación de un trayecto crea cursos en el suyo.
  """
  use Amauta.Action,
    name: "courses.course.create",
    description: "Crea un curso.",
    params: [
      name: {:string, required: true},
      code: :string,
      slug: :string,
      description: :string,
      icon: :string,
      color: :string,
      period_id: Ecto.UUID,
      pathway_id: Ecto.UUID,
      stage_id: Ecto.UUID,
      required: :boolean
    ]

  alias Amauta.Courses
  alias Amauta.Courses.Actions.Helpers

  @impl true
  def authorize(scope, input),
    do: Helpers.authorize_in_pathway(scope, input[:pathway_id], "institution.courses.create")

  @impl true
  def run(scope, input), do: Courses.create(scope, input)
end

defmodule Amauta.Courses.Actions.UpdateCourse do
  @moduledoc """
  Edita los datos de un curso (RF-CUR-001). Sacarlo de un trayecto o
  llevarlo a otro exige, además, editar la estructura de esos trayectos.
  """
  use Amauta.Action,
    name: "courses.course.update",
    description: "Edita los datos de un curso.",
    params: [
      course_id: {Ecto.UUID, required: true},
      name: :string,
      code: :string,
      slug: :string,
      description: :string,
      icon: :string,
      color: :string,
      period_id: Ecto.UUID,
      pathway_id: Ecto.UUID,
      stage_id: Ecto.UUID,
      required: :boolean
    ]

  alias Amauta.{Authorization, Courses}
  alias Amauta.Courses.Actions.Helpers

  @impl true
  def authorize(scope, %{course_id: id} = input) do
    with {:ok, course} <- Helpers.fetch_course(scope, id),
         :ok <- Authorization.authorize(scope, "course.update", course) do
      authorize_move(scope, course, input)
    end
  end

  defp authorize_move(scope, course, %{pathway_id: new} = _input) when new != course.pathway_id do
    permission = "pathway.structure.update"

    with :ok <- maybe_authorize(scope, course.pathway_id, permission) do
      maybe_authorize(scope, new, permission)
    end
  end

  defp authorize_move(_scope, _course, _input), do: :ok

  defp maybe_authorize(_scope, nil, _permission), do: :ok

  defp maybe_authorize(scope, id, permission),
    do: Helpers.authorize_in_pathway(scope, id, permission)

  @impl true
  def run(scope, %{course_id: id} = input) do
    with {:ok, course} <- Helpers.fetch_editable_course(scope, id) do
      Courses.update(scope, course, Map.delete(input, :course_id))
    end
  end
end

defmodule Amauta.Courses.Actions.UpdateCourseSettings do
  @moduledoc "Cambia los ajustes de un curso (RF-CUR-007)."
  use Amauta.Action,
    name: "courses.course.update_settings",
    description: "Cambia los ajustes de un curso.",
    params: [
      course_id: {Ecto.UUID, required: true},
      settings: {:map, required: true}
    ]

  alias Amauta.Courses.Actions.Helpers
  alias Amauta.Courses.Course
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(scope, %{course_id: id}), do: Helpers.authorize_course(scope, id, "course.update")

  @impl true
  def run(scope, %{course_id: id, settings: settings}) do
    with {:ok, course} <- Helpers.fetch_editable_course(scope, id) do
      course
      |> Course.settings_changeset(%{settings: settings})
      |> Repo.update(Tenancy.opts(scope))
    end
  end
end

defmodule Amauta.Courses.Actions.RegenerateEnrollmentCode do
  @moduledoc """
  Genera un código de inscripción nuevo: el anterior deja de servir. Útil
  si el código circuló donde no debía.
  """
  use Amauta.Action,
    name: "courses.course.regenerate_enrollment_code",
    description: "Genera un código de inscripción nuevo.",
    params: [course_id: {Ecto.UUID, required: true}]

  alias Amauta.Courses
  alias Amauta.Courses.Actions.Helpers

  @impl true
  def authorize(scope, %{course_id: id}), do: Helpers.authorize_course(scope, id, "course.update")

  @impl true
  def run(scope, %{course_id: id}) do
    with {:ok, course} <- Helpers.fetch_editable_course(scope, id) do
      Courses.regenerate_enrollment_code(scope, course)
    end
  end
end

defmodule Amauta.Courses.Actions.PublishCourse do
  @moduledoc "Publica un curso en borrador: sus participantes pueden verlo."
  use Amauta.Action,
    name: "courses.course.publish",
    description: "Publica un curso.",
    params: [course_id: {Ecto.UUID, required: true}]

  alias Amauta.Courses.Actions.Helpers

  @impl true
  def authorize(scope, %{course_id: id}), do: Helpers.authorize_course(scope, id, "course.update")

  @impl true
  def run(scope, %{course_id: id}), do: Helpers.transition(scope, id, ~w(draft), "published")
end

defmodule Amauta.Courses.Actions.ArchiveCourse do
  @moduledoc "Archiva un curso: queda de solo lectura (ERS 4.8)."
  use Amauta.Action,
    name: "courses.course.archive",
    description: "Archiva un curso.",
    params: [course_id: {Ecto.UUID, required: true}]

  alias Amauta.Courses.Actions.Helpers

  @impl true
  def authorize(scope, %{course_id: id}),
    do: Helpers.authorize_course(scope, id, "course.archive")

  @impl true
  def run(scope, %{course_id: id}),
    do: Helpers.transition(scope, id, ~w(draft published), "archived")
end

defmodule Amauta.Courses.Actions.ReopenCourse do
  @moduledoc "Reabre un curso archivado: vuelve a publicado."
  use Amauta.Action,
    name: "courses.course.reopen",
    description: "Reabre un curso archivado.",
    params: [course_id: {Ecto.UUID, required: true}]

  alias Amauta.Courses.Actions.Helpers

  @impl true
  def authorize(scope, %{course_id: id}),
    do: Helpers.authorize_course(scope, id, "course.archive")

  @impl true
  def run(scope, %{course_id: id}), do: Helpers.transition(scope, id, ~w(archived), "published")
end
