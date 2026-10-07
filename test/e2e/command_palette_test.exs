defmodule AmautaWeb.E2E.CommandPaletteTest do
  @moduledoc """
  Prueba en navegador real (Playwright): la paleta de comandos con el
  teclado (RF-UI-003).
  """
  use AmautaWeb.E2ECase

  alias Amauta.Actions
  alias Amauta.Courses.Actions.{CreateCourse, PublishCourse}
  alias AmautaWeb.Paths

  setup do
    user = user_fixture()
    assign!(user, "institution_admin", :institution)
    admin = Amauta.Scope.for_user(institution(), user)
    {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Programación I"})
    {:ok, course} = Actions.run(PublishCourse, admin, %{"course_id" => course.id})
    %{user: user, course: course}
  end

  test "Ctrl+K abre la paleta, busca y navega con el teclado", %{
    conn: conn,
    user: user,
    course: course
  } do
    conn
    |> log_in(user)
    |> press("body", "Control+k")
    |> assert_has("#command-palette [role=dialog]")
    |> type("#command-palette [data-input]", "progra")
    |> assert_has("#command-palette-course-#{course.id}")
    |> press("#command-palette [data-input]", "Enter")
    |> assert_has("h1", text: "Programación I")
    |> assert_path(Paths.course(institution(), course))
  end

  test "Esc cierra la paleta y «?» muestra los atajos", %{conn: conn, user: user} do
    conn
    |> log_in(user)
    |> press("body", "Control+k")
    |> assert_has("#command-palette [role=dialog]")
    |> press("#command-palette [data-input]", "Escape")
    |> refute_has("#command-palette [role=dialog]")
    |> press("body", "?")
    |> assert_has("#command-palette", text: "Keyboard shortcuts")
  end
end
