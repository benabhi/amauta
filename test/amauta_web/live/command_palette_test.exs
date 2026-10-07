defmodule AmautaWeb.CommandPaletteTest do
  @moduledoc "Paleta de comandos (RF-BUS-001 y RF-UI-003): accesos y búsqueda con permisos."
  use AmautaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.Actions
  alias Amauta.Courses.Actions.{CreateCourse, PublishCourse}
  alias Amauta.Pathways.Actions.CreatePathway
  alias AmautaWeb.Paths

  setup do
    admin = member_scope("institution_admin")
    {:ok, published} = Actions.run(CreateCourse, admin, %{"name" => "Programación I"})
    {:ok, published} = Actions.run(PublishCourse, admin, %{"course_id" => published.id})
    {:ok, draft} = Actions.run(CreateCourse, admin, %{"name" => "Programación II"})
    {:ok, pathway} = Actions.run(CreatePathway, admin, %{"name" => "Lic. en Programación"})
    %{admin: admin, published: published, draft: draft, pathway: pathway}
  end

  defp search(view, q) do
    view |> element("#command-palette form") |> render_change(%{"q" => q})
  end

  test "está en todas las pantallas, con sus accesos según los permisos", %{
    conn: conn,
    admin: admin
  } do
    {:ok, view, _html} = conn |> log_in_user(admin.user) |> live(Paths.home(institution()))

    assert has_element?(
             view,
             ~s(#command-palette-action-people[href="#{Paths.people(institution())}"])
           )

    assert has_element?(view, "#command-palette-action-new-course")
    assert has_element?(view, "#command-palette-action-periods")

    {:ok, view, _html} =
      conn |> log_in_user(user_fixture()) |> live(Paths.courses(institution()))

    assert has_element?(view, "#command-palette-action-courses")
    refute has_element?(view, "#command-palette-action-people")
    refute has_element?(view, "#command-palette-action-new-course")
  end

  test "busca cursos, trayectos y personas", ctx do
    %{conn: conn, admin: admin, published: published, draft: draft, pathway: pathway} = ctx
    person = user_fixture(first_name: "Programina", last_name: "Quispe")

    {:ok, view, _html} = conn |> log_in_user(admin.user) |> live(Paths.home(institution()))
    search(view, "program")

    assert has_element?(
             view,
             ~s(#command-palette-course-#{published.id}[href="#{Paths.course(institution(), published)}"])
           )

    assert has_element?(view, "#command-palette-course-#{draft.id}")
    assert has_element?(view, "#command-palette-pathway-#{pathway.id}")
    assert has_element?(view, "#command-palette-person-#{person.id}")
  end

  test "un estudiante no encuentra borradores ni personas", ctx do
    %{conn: conn, published: published, draft: draft} = ctx
    user_fixture(first_name: "Programina")
    student = user_fixture()
    assign!(student, "student", :institution)

    {:ok, view, _html} = conn |> log_in_user(student) |> live(Paths.home(institution()))
    search(view, "program")

    assert has_element?(view, "#command-palette-course-#{published.id}")
    refute has_element?(view, "#command-palette-course-#{draft.id}")
    refute has_element?(view, "[id^=command-palette-person-]")
  end

  test "filtra los accesos sin importar tildes y avisa si no hay nada", %{
    conn: conn,
    admin: admin
  } do
    {:ok, view, _html} = conn |> log_in_user(admin.user) |> live(Paths.home(institution()))

    search(view, "periodos")
    assert has_element?(view, "#command-palette-action-periods")
    refute has_element?(view, "#command-palette-action-home")

    html = search(view, "zzzz")
    assert html =~ "Nothing matches «zzzz»."
  end
end
