defmodule AmautaWeb.EnrollmentCodeVisibilityTest do
  @moduledoc """
  Bug: el código de inscripción del encabezado (RF-CUR-003, «para
  docentes») solo lo veía quien podía editar el curso o matricular; los
  docentes y ayudantes, que son quienes lo comparten en clase, no.
  """
  use AmautaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Actions, Enrollments}
  alias Amauta.Courses.Actions.{CreateCourse, PublishCourse, UpdateCourseSettings}
  alias Amauta.Enrollments.Actions.CreateSection
  alias AmautaWeb.Paths

  setup do
    admin = member_scope("institution_admin")
    {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Programación I"})
    {:ok, course} = Actions.run(PublishCourse, admin, %{"course_id" => course.id})

    {:ok, course} =
      Actions.run(UpdateCourseSettings, admin, %{
        "course_id" => course.id,
        "settings" => %{"enrollment_code_enabled" => "true"}
      })

    {:ok, section} = Actions.run(CreateSection, admin, %{"course_id" => course.id, "name" => "A"})
    %{course: course, section: section}
  end

  defp sees_code?(conn, course, role, section \\ nil) do
    user = user_fixture()

    {:ok, _} =
      Enrollments.enroll(institution(), course, user.id, %{
        role: role,
        origin: "manual",
        section_id: section && section.id
      })

    {:ok, view, _html} = conn |> log_in_user(user) |> live(Paths.course(institution(), course))
    has_element?(view, "#enrollment-code", course.enrollment_code)
  end

  test "lo ve todo el equipo docente", %{conn: conn, course: course, section: section} do
    assert sees_code?(conn, course, "course_lead")
    assert sees_code?(conn, course, "teacher")
    assert sees_code?(conn, course, "assistant")
    assert sees_code?(conn, course, "teacher", section)
  end

  test "no lo ven estudiantes ni observadores", %{conn: conn, course: course} do
    refute sees_code?(conn, course, "student")
    refute sees_code?(conn, course, "observer")
  end
end
