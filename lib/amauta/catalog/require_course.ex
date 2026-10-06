defmodule Amauta.Catalog.RequireCourse do
  @moduledoc """
  El curso de `course_id` tiene que existir en la institución; si no, la
  acción falla con «no encontrado» (igual que un ID de otra institución).
  `Change` se usa en acciones de creación y `Preparation`, en lecturas.
  """
  alias Amauta.Catalog.Course

  def check(course_id, tenant) do
    case course_id && Ash.get(Course, course_id, tenant: tenant, authorize?: false) do
      {:ok, %Course{}} ->
        :ok

      _ ->
        {:error,
         Ash.Error.Query.NotFound.exception(resource: Course, primary_key: %{id: course_id})}
    end
  end

  defmodule Change do
    @moduledoc false
    use Ash.Resource.Change

    @impl true
    def change(changeset, _opts, _context) do
      Ash.Changeset.before_action(changeset, fn changeset ->
        course_id = Ash.Changeset.get_argument_or_attribute(changeset, :course_id)

        case Amauta.Catalog.RequireCourse.check(course_id, changeset.tenant) do
          :ok -> changeset
          {:error, error} -> Ash.Changeset.add_error(changeset, error)
        end
      end)
    end
  end

  defmodule Preparation do
    @moduledoc false
    use Ash.Resource.Preparation

    @impl true
    def prepare(query, _opts, _context) do
      Ash.Query.before_action(query, fn query ->
        course_id = Ash.Query.get_argument(query, :course_id)

        case Amauta.Catalog.RequireCourse.check(course_id, query.tenant) do
          :ok -> query
          {:error, error} -> Ash.Query.add_error(query, error)
        end
      end)
    end
  end
end
