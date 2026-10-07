defmodule AmautaWeb.HomeLiveTest do
  @moduledoc "Inicio adaptado al rol (RF-INS-002, RF-UI-001)."
  use AmautaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Accounts, Actions, Enrollments, Home}
  alias Amauta.Courses.Actions.{CreateCourse, PublishCourse}
  alias Amauta.Enrollments.Actions.CreateSection
  alias AmautaWeb.Paths

  setup do
    admin = member_scope("institution_admin")
    {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Programación I"})
    {:ok, course} = Actions.run(PublishCourse, admin, %{"course_id" => course.id})
    {:ok, draft} = Actions.run(CreateCourse, admin, %{"name" => "Borrador"})
    %{admin: admin, course: course, draft: draft}
  end

  defp enroll!(course, user, role, section \\ nil) do
    {:ok, _} =
      Enrollments.enroll(institution(), course, user.id, %{
        role: role,
        origin: "manual",
        section_id: section && section.id
      })
  end

  test "un estudiante ve sus cursos publicados y su panel, sin indicadores", ctx do
    %{conn: conn, course: course, draft: draft} = ctx
    student = user_fixture()
    enroll!(course, student, "student")
    enroll!(draft, student, "student")

    {:ok, view, _html} = conn |> log_in_user(student) |> live(Paths.home(institution()))

    assert has_element?(view, "#my-course-#{course.id}")
    refute has_element?(view, "#my-course-#{draft.id}")
    assert has_element?(view, "#to-do")
    refute has_element?(view, "#to-review")
    refute has_element?(view, "#institution-overview")
  end

  test "un docente ve también sus borradores, con su rol, y «Para revisar»", ctx do
    %{conn: conn, draft: draft} = ctx
    teacher = user_fixture()
    enroll!(draft, teacher, "course_lead")

    {:ok, view, _html} = conn |> log_in_user(teacher) |> live(Paths.home(institution()))

    assert has_element?(view, "#my-course-#{draft.id}", "Lead teacher")
    assert has_element?(view, "#to-review")
    refute has_element?(view, "#to-do")
  end

  test "sin cursos, invita a sumarse con un código", %{conn: conn} do
    {:ok, view, html} = conn |> log_in_user(user_fixture()) |> live(Paths.home(institution()))
    assert html =~ "You have no cursos yet"
    assert has_element?(view, ~s(a[href="#{Paths.join(institution())}"]))
  end

  test "la administración ve indicadores y pendientes con sus enlaces", ctx do
    %{conn: conn, admin: admin, course: course} = ctx
    {:ok, _invited} = Accounts.register_user(admin, valid_user_attributes())
    {:ok, section} = Actions.run(CreateSection, admin, %{"course_id" => course.id, "name" => "A"})
    enroll!(course, user_fixture(), "student")
    enroll!(course, user_fixture(), "student", section)

    {:ok, view, _html} = conn |> log_in_user(admin.user) |> live(Paths.home(institution()))

    assert has_element?(view, "#stat-courses", "1")
    assert has_element?(view, "#stat-enrollments", "2")

    assert has_element?(
             view,
             ~s(#pending-invitations a[href="#{Paths.people(institution(), %{"status" => "invited"})}"])
           )

    assert has_element?(view, "#pending-drafts", "In draft: 1 curso")
    assert has_element?(view, "#pending-without_teachers")
    assert has_element?(view, "#pending-without_section", "1 student")
  end

  test "los pendientes desaparecen cuando se resuelven", %{
    admin: admin,
    course: course,
    draft: draft
  } do
    enroll!(course, user_fixture(), "teacher")
    {:ok, _} = Actions.run(PublishCourse, admin, %{"course_id" => draft.id})
    enroll!(draft, user_fixture(), "teacher")

    pending = Keyword.keys(Home.pending(admin))
    refute :drafts in pending
    refute :without_teachers in pending
    refute :without_section in pending
  end

  test "los indicadores son de la institución propia", %{admin: admin} do
    b = Amauta.Fixtures.institution_fixture("inst_test_b")
    assert %{published_courses: 1, draft_courses: 1} = Home.stats(admin)
    assert %{published_courses: 0, draft_courses: 0} = Home.stats(b)
  end
end
