defmodule AmautaWeb.E2E.CommandPaletteTest do
  @moduledoc """
  Prueba en navegador real (Playwright): entrar con contraseña y usar la
  paleta de comandos con el teclado (RF-UI-003). Se corre con `bin/dev e2e`.
  """
  use PhoenixTest.Playwright.Case, async: true

  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.Actions
  alias Amauta.Courses.Actions.{CreateCourse, PublishCourse}
  alias AmautaWeb.Paths

  @moduletag :e2e

  setup do
    user = user_fixture() |> set_password()
    assign!(user, "institution_admin", :institution)
    admin = Amauta.Scope.for_user(institution(), user)
    {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Programación I"})
    {:ok, course} = Actions.run(PublishCourse, admin, %{"course_id" => course.id})
    %{user: user, course: course}
  end

  defp log_in(conn, user) do
    conn
    |> visit(Paths.log_in(institution()))
    # Esperar a que la LiveView conecte: si se escribe antes, al conectar
    # vuelve a dibujar el formulario y lo vacía.
    |> assert_has("[data-phx-main].phx-connected")
    |> within("#login_form_password", fn session ->
      session
      |> fill_in("Email", with: user.email)
      |> fill_in("Password", with: valid_user_password())
      |> click_button("Log in only this time")
    end)
    # assert_path no reintenta: primero se espera algo propio del inicio
    # (assert_has sí reintenta) y la conexión de su LiveView.
    |> assert_has("#my-courses")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_path(Paths.home(institution()))
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
