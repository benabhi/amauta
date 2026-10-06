defmodule Amauta.TenancyTest do
  @moduledoc "Tests de fuga entre instituciones (RNF-SEG-002)."
  use Amauta.DataCase, async: true

  import Amauta.Fixtures
  alias Amauta.Feed
  alias Amauta.Feed.Post

  setup do
    a = institution_fixture("inst_test_a")
    b = institution_fixture("inst_test_b")
    %{a: a, b: b}
  end

  test "Ash exige la institución y el Repo rechaza consultas sin prefijo" do
    assert_raise Ash.Error.Invalid, ~r/require a tenant/, fn ->
      Feed.list_posts!(Ecto.UUID.generate(), authorize?: false)
    end

    assert_raise Amauta.MissingPrefixError, fn -> Repo.all(Post) end
  end

  test "los datos de una institución no se ven desde otra", %{a: a, b: b} do
    course_a = course_fixture(a, %{slug: "prog1"})
    course_b = course_fixture(b, %{slug: "prog1"})
    teacher_a = member_fixture(a, "teacher", course_a)

    Feed.create_post!(%{course_id: course_a.id, body: "Solo para A"},
      scope: scope_fixture(a, teacher_a)
    )

    assert [%Post{body: "Solo para A"}] =
             Feed.list_posts!(course_a.id, tenant: a, authorize?: false)

    assert [] = Feed.list_posts!(course_b.id, tenant: b, authorize?: false)
  end

  test "un ID de otra institución no se encuentra", %{a: a, b: b} do
    course_b = course_fixture(b)
    scope = scope_fixture(a, member_fixture(a, "institution_admin"))

    assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
             Feed.list_posts(course_b.id, scope: scope)

    assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
             Feed.create_post(%{course_id: course_b.id, body: "x"}, scope: scope)
  end
end
