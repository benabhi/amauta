defmodule Amauta.TenancyTest do
  @moduledoc "Tests de fuga entre instituciones (RNF-SEG-002)."
  use Amauta.DataCase, async: true

  import Amauta.Fixtures
  alias Amauta.{Actions, Feed}
  alias Amauta.Feed.Actions.{CreatePost, ListPosts}
  alias Amauta.Feed.Post

  setup do
    a = institution_fixture("inst_test_a")
    b = institution_fixture("inst_test_b")
    %{a: a, b: b}
  end

  test "el Repo rechaza consultas sin prefijo" do
    assert_raise Amauta.Tenancy.MissingPrefixError, fn -> Repo.all(Post) end
    assert_raise Amauta.Tenancy.MissingPrefixError, fn -> Repo.get(Post, Ecto.UUID.generate()) end
  end

  test "los datos de una institución no se ven desde otra", %{a: a, b: b} do
    course_a = course_fixture(a, %{slug: "prog1"})
    course_b = course_fixture(b, %{slug: "prog1"})
    teacher_a = member_fixture(a, "teacher", course_a)

    {:ok, _} =
      Actions.run(CreatePost, scope_fixture(a, teacher_a), %{
        "course_id" => course_a.id,
        "body" => "Solo para A"
      })

    assert [%Post{body: "Solo para A"}] = Feed.list_posts(a, course_a)
    assert [] = Feed.list_posts(b, course_b)
  end

  test "un ID de otra institución no se encuentra", %{a: a, b: b} do
    course_b = course_fixture(b)
    admin_a = member_fixture(a, "institution_admin")
    scope = scope_fixture(a, admin_a)

    assert {:error, :not_found} = Actions.run(ListPosts, scope, %{"course_id" => course_b.id})

    assert {:error, :not_found} =
             Actions.run(CreatePost, scope, %{"course_id" => course_b.id, "body" => "x"})
  end
end
