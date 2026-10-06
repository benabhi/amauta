defmodule Amauta.Authorization.Checks.HasCoursePermission do
  @moduledoc """
  Política: el actor (un `Amauta.Scope`) tiene el permiso en el curso que
  indica el argumento o atributo `course_id` de la acción.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(opts), do: "actor has #{opts[:permission]} in the course"

  @impl true
  def match?(%Amauta.Scope{} = scope, %{subject: subject}, opts) do
    case course_id(subject) do
      nil -> false
      course_id -> Amauta.Authorization.Effective.allowed?(scope, opts[:permission], course_id)
    end
  end

  def match?(_actor, _context, _opts), do: false

  defp course_id(%Ash.Changeset{} = changeset),
    do: Ash.Changeset.get_argument_or_attribute(changeset, :course_id)

  defp course_id(%Ash.Query{} = query), do: Ash.Query.get_argument(query, :course_id)
  defp course_id(_), do: nil
end
