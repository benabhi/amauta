defmodule AmautaWeb.E2E.CourseHeaderTest do
  @moduledoc """
  Bug: en el encabezado del curso, el equipo docente (avatares) quedaba más
  arriba que el recuadro del código de inscripción. Se mide en un navegador
  real que los dos estén centrados en la misma línea.
  """
  use PhoenixTest.Playwright.Case, async: true

  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Actions, Enrollments}
  alias Amauta.Courses.Actions.{CreateCourse, PublishCourse, UpdateCourseSettings}
  alias AmautaWeb.Paths

  @moduletag :e2e

  setup do
    user = user_fixture() |> set_password()
    assign!(user, "institution_admin", :institution)
    admin = Amauta.Scope.for_user(institution(), user)
    {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Programación I"})
    {:ok, course} = Actions.run(PublishCourse, admin, %{"course_id" => course.id})

    {:ok, _} =
      Actions.run(UpdateCourseSettings, admin, %{
        "course_id" => course.id,
        "settings" => %{"enrollment_code_enabled" => "true"}
      })

    {:ok, _} =
      Enrollments.enroll(admin, course, user_fixture().id, %{
        role: "course_lead",
        origin: "manual"
      })

    %{user: user, course: course}
  end

  test "el equipo docente y el código de inscripción están alineados", ctx do
    %{conn: conn, user: user, course: course} = ctx

    conn
    |> visit(Paths.log_in(institution()))
    |> assert_has("[data-phx-main].phx-connected")
    |> within("#login_form_password", fn session ->
      session
      |> fill_in("Email", with: user.email)
      |> fill_in("Password", with: valid_user_password())
      |> click_button("Log in only this time")
    end)
    |> assert_has("#my-courses")
    |> visit(Paths.course(institution(), course))
    |> assert_has("#enrollment-code")
    |> assert_has("#teaching-team")
    |> evaluate(
      """
      (() => {
        const center = (el) => {
          const r = el.getBoundingClientRect()
          return r.top + r.height / 2
        }
        const avatar = document.querySelector("#teaching-team > *")
        return Math.abs(center(avatar) - center(document.getElementById("enrollment-code")))
      })()
      """,
      fn difference -> assert difference <= 1 end
    )
  end
end
