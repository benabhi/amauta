defmodule AmautaWeb.CourseFeedTest do
  @moduledoc "Pestaña Tablón: publicar, borrador, tiempo real, edición y permisos."
  use AmautaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Actions, Enrollments, Feed}
  alias Amauta.Courses.Actions.{CreateCourse, PublishCourse}
  alias Amauta.Enrollments.Actions.CreateSection
  alias Amauta.Feed.Actions.PublishPost
  alias AmautaWeb.Paths

  setup do
    admin = member_scope("institution_admin")
    {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Programación I"})
    {:ok, course} = Actions.run(PublishCourse, admin, %{"course_id" => course.id})

    {:ok, a} =
      Actions.run(CreateSection, admin, %{"course_id" => course.id, "name" => "Comisión A"})

    %{course: course, a: a}
  end

  defp body(text),
    do:
      Jason.encode!(%{
        "type" => "doc",
        "content" => [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}
        ]
      })

  defp member(course, role, section \\ nil) do
    user = user_fixture()

    {:ok, _} =
      Enrollments.enroll(institution(), course, user.id, %{
        role: role,
        origin: "manual",
        section_id: section && section.id
      })

    user
  end

  test "el equipo docente publica desde el editor y aparece arriba", %{conn: conn, course: course} do
    teacher = member(course, "teacher")
    {:ok, view, _html} = conn |> log_in_user(teacher) |> live(Paths.course(institution(), course))

    view
    |> form("#feed-composer")
    |> render_submit(%{post: %{body: body("Bienvenidos a Programación I")}})

    assert has_element?(view, "#feed-posts article", "Bienvenidos a Programación I")
    refute has_element?(view, "#feed-composer [data-editor-input][value*=Bienvenidos]")
  end

  test "el borrador se guarda al escribir y vuelve al recargar", %{conn: conn, course: course} do
    teacher = member(course, "teacher")
    conn = log_in_user(conn, teacher)
    {:ok, view, _html} = live(conn, Paths.course(institution(), course))

    view |> form("#feed-composer") |> render_change(%{post: %{body: body("A medio escribir")}})

    {:ok, view, _html} = live(conn, Paths.course(institution(), course))
    assert has_element?(view, "#feed-composer [data-editor-input][value*=\"A medio escribir\"]")
  end

  test "lo nuevo llega en tiempo real a quien mira el tablón", %{conn: conn, course: course, a: a} do
    teacher = member(course, "teacher")
    in_a = member(course, "student", a)
    outside = member(course, "student")

    {:ok, view_a, _} = conn |> log_in_user(in_a) |> live(Paths.course(institution(), course))

    {:ok, view_out, _} =
      build_conn() |> log_in_user(outside) |> live(Paths.course(institution(), course))

    {:ok, post} =
      Actions.run(PublishPost, Amauta.Scope.for_user(institution(), teacher), %{
        "course_id" => course.id,
        "body" => body("Solo para la A"),
        "section_id" => a.id
      })

    # send_update llega en un mensaje aparte: el primer render lo deja pasar.
    _ = render(view_a)
    _ = render(view_out)
    assert render(view_a) =~ "Solo para la A"
    refute render(view_out) =~ "Solo para la A"

    {:ok, _} =
      Actions.run(
        Amauta.Feed.Actions.DeletePost,
        Amauta.Scope.for_user(institution(), teacher),
        %{"post_id" => post.id}
      )

    _ = render(view_a)
    refute render(view_a) =~ "Solo para la A"
  end

  test "un estudiante no ve el editor si no puede publicar", %{conn: conn, course: course} do
    student = member(course, "student")
    {:ok, view, _html} = conn |> log_in_user(student) |> live(Paths.course(institution(), course))
    refute has_element?(view, "#feed-composer")
    assert has_element?(view, "#course-feed", "Nothing posted yet")
  end

  test "edita la publicación propia y queda la marca", %{conn: conn, course: course} do
    teacher = member(course, "teacher")
    scope = Amauta.Scope.for_user(institution(), teacher)

    {:ok, post} =
      Actions.run(PublishPost, scope, %{
        "course_id" => course.id,
        "body" => body("Clase el lunes")
      })

    {:ok, view, _html} = conn |> log_in_user(teacher) |> live(Paths.course(institution(), course))

    view
    |> element(~s(#feed-posts [phx-click="edit"][phx-value-id="#{post.id}"]))
    |> render_click()

    view
    |> form("#edit-post-#{post.id}")
    |> render_submit(%{edit: %{body: body("Clase el martes")}})

    assert has_element?(view, "#feed-posts article", "Clase el martes")
    assert has_element?(view, "#feed-posts article", "edited")
    assert [%{edited_at: %DateTime{}}] = Feed.list_posts(scope, course)
  end
end
