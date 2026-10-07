defmodule AmautaWeb.E2E.CopyCodeTest do
  @moduledoc "Copiar el código de inscripción al portapapeles desde el encabezado del curso."
  use AmautaWeb.E2ECase

  alias Amauta.Actions
  alias Amauta.Courses.Actions.{CreateCourse, PublishCourse, UpdateCourseSettings}
  alias AmautaWeb.Paths

  setup do
    user = user_fixture()
    assign!(user, "institution_admin", :institution)
    admin = Amauta.Scope.for_user(institution(), user)
    {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Programación I"})
    {:ok, course} = Actions.run(PublishCourse, admin, %{"course_id" => course.id})

    {:ok, course} =
      Actions.run(UpdateCourseSettings, admin, %{
        "course_id" => course.id,
        "settings" => %{"enrollment_code_enabled" => "true"}
      })

    %{user: user, course: course}
  end

  test "copia el código y muestra que se copió", %{conn: conn, user: user, course: course} do
    conn
    |> log_in(user, Paths.course(institution(), course))
    # El portapapeles real pide permisos al navegador: se registra lo copiado.
    |> evaluate("""
    navigator.clipboard.writeText = (text) => {
      window.copied = text
      return Promise.resolve()
    }
    """)
    |> refute_has("#enrollment-code [data-icon=copied]")
    |> assert_has("#enrollment-code [data-icon=copy]")
    |> click("#enrollment-code button[data-copy]")
    |> assert_has("#enrollment-code [data-icon=copied]")
    |> refute_has("#enrollment-code [data-icon=copy]")
    |> assert_has("#enrollment-code button[data-copied]")
    |> assert_has("#enrollment-code [data-copy-status]", text: "Copied")
    |> evaluate("window.copied", fn copied -> assert copied == course.enrollment_code end)
  end
end
