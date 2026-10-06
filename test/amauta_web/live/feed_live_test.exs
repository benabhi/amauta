defmodule AmautaWeb.FeedLiveTest do
  use AmautaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Amauta.Fixtures
  alias AmautaWeb.Paths

  setup do
    institution = institution_fixture()
    course = course_fixture(institution, %{name: "Programación I"})

    %{
      institution: institution,
      course: course,
      teacher: member_fixture(institution, "teacher", course),
      student: member_fixture(institution, "student", course)
    }
  end

  defp login(conn, institution, user) do
    get(conn, Paths.dev_login(institution, user, "/")) |> recycle()
  end

  test "la docente publica y la estudiante lo ve en tiempo real", ctx do
    path = Paths.course_feed(ctx.institution, ctx.course)

    {:ok, student_view, html} = live(login(ctx.conn, ctx.institution, ctx.student), path)
    assert html =~ "Programación I"
    refute has_element?(student_view, "#post-form")

    {:ok, teacher_view, _html} = live(login(build_conn(), ctx.institution, ctx.teacher), path)

    teacher_view
    |> form("#post-form", post: %{body: "Mañana no hay clase"})
    |> render_submit()

    assert has_element?(teacher_view, "#posts", "Mañana no hay clase")
    assert render(student_view) =~ "Mañana no hay clase"
  end

  test "valida el cuerpo vacío", ctx do
    {:ok, view, _} =
      live(
        login(ctx.conn, ctx.institution, ctx.teacher),
        Paths.course_feed(ctx.institution, ctx.course)
      )

    assert view |> form("#post-form", post: %{body: "   "}) |> render_submit() =~
             "is required"
  end

  test "sin sesión no se puede ver el tablón", ctx do
    assert_error_sent 403, fn ->
      get(ctx.conn, Paths.course_feed(ctx.institution, ctx.course))
    end
  end

  test "una institución inexistente da 404", ctx do
    assert_error_sent 404, fn -> get(ctx.conn, "/no-existe/c/#{ctx.course.slug}/feed") end
  end
end
