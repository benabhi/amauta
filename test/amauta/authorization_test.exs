defmodule Amauta.AuthorizationTest do
  @moduledoc "Matriz de autorización de las acciones del tablón."
  use Amauta.DataCase, async: true

  import Amauta.Fixtures
  alias Amauta.{Actions, Audit}
  alias Amauta.Feed.Actions.{CreatePost, ListPosts}

  # rol → ámbito → {puede listar, puede publicar}
  @matrix [
    {"institution_admin", :institution, {:ok, :ok}},
    {"teacher", :course, {:ok, :ok}},
    {"assistant", :course, {:ok, :forbidden}},
    {"student", :course, {:ok, :forbidden}},
    {"observer", :course, {:ok, :forbidden}},
    {"teacher", :other_course, {:forbidden, :forbidden}},
    {nil, nil, {:forbidden, :forbidden}}
  ]

  setup do
    institution = institution_fixture()
    %{institution: institution, course: course_fixture(institution)}
  end

  for {role, scope_kind, {list, create}} <- @matrix do
    test "#{role || "sin rol"} en #{scope_kind || "ningún ámbito"}: listar #{list}, publicar #{create}",
         %{institution: institution, course: course} do
      user = user_for(institution, course, unquote(role), unquote(scope_kind))
      scope = scope_fixture(institution, user)
      params = %{"course_id" => course.id, "body" => "Hola"}

      assert result(Actions.run(ListPosts, scope, params)) == unquote(list)
      assert result(Actions.run(CreatePost, scope, params)) == unquote(create)
    end
  end

  test "publicar deja un evento de auditoría y listar no", %{institution: i, course: course} do
    scope = scope_fixture(i, member_fixture(i, "teacher", course))

    {:ok, _} = Actions.run(ListPosts, scope, %{"course_id" => course.id})
    {:ok, post} = Actions.run(CreatePost, scope, %{"course_id" => course.id, "body" => "Hola"})

    assert [event] = Audit.list_events(i)
    assert event.action == "feed.post.create"
    assert event.subject_id == post.id
    assert event.actor_id == scope.user.id
  end

  test "un error de validación no audita", %{institution: i, course: course} do
    scope = scope_fixture(i, member_fixture(i, "teacher", course))

    assert {:error, %Ecto.Changeset{}} =
             Actions.run(CreatePost, scope, %{"course_id" => course.id, "body" => "  "})

    assert [] = Audit.list_events(i)
  end

  defp user_for(_institution, _course, nil, _), do: nil
  defp user_for(i, _course, role, :institution), do: member_fixture(i, role)
  defp user_for(i, course, role, :course), do: member_fixture(i, role, course)
  defp user_for(i, _course, role, :other_course), do: member_fixture(i, role, course_fixture(i))

  defp result({:ok, _}), do: :ok
  defp result({:error, :forbidden}), do: :forbidden
end
