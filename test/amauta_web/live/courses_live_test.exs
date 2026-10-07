defmodule AmautaWeb.CoursesLiveTest do
  @moduledoc "Pantallas de cursos: lista, alta, pestañas y ajustes."
  use AmautaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Actions, Courses}
  alias Amauta.Courses.Actions.{CreateCourse, PublishCourse}
  alias Amauta.Pathways.Actions.{AddStage, CreatePathway}
  alias AmautaWeb.Paths

  defp log_in_as(conn, role, scope \\ :institution) do
    user = user_fixture()
    assign!(user, role, scope)
    {log_in_user(conn, user), user}
  end

  defp create_course(attrs) do
    {:ok, course} = Actions.run(CreateCourse, member_scope("institution_admin"), attrs)
    course
  end

  describe "lista y alta" do
    test "crea un curso y lleva a su tablón", %{conn: conn} do
      {conn, _admin} = log_in_as(conn, "institution_admin")
      {:ok, view, _html} = live(conn, Paths.new_course(institution()))

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("#course_form", course: %{name: "Programación I", code: "PROG1"})
               |> render_submit()

      assert to == "/#{institution().slug}/c/programacion-i"
    end

    test "al elegir un trayecto aparecen sus etapas", %{conn: conn} do
      {conn, admin} = log_in_as(conn, "institution_admin")
      scope = Amauta.Scope.for_user(institution(), admin)
      {:ok, pathway} = Actions.run(CreatePathway, scope, %{"name" => "Lic. en Sistemas"})

      {:ok, stage} =
        Actions.run(AddStage, scope, %{"pathway_id" => pathway.id, "name" => "1.er año"})

      {:ok, view, _html} = live(conn, Paths.new_course(institution(), %{pathway_id: pathway.id}))
      assert has_element?(view, ~s(#course_form option[value="#{stage.id}"]))

      view
      |> form("#course_form",
        course: %{name: "Taller", pathway_id: pathway.id, stage_id: stage.id, required: "false"}
      )
      |> render_submit()

      assert %{stage_id: sid, required: false} = Courses.get_by_slug(institution(), "taller")
      assert sid == stage.id
    end

    test "los borradores solo los ve quien puede editarlos", %{conn: conn} do
      draft = create_course(%{"name" => "Borrador"})
      published = create_course(%{"name" => "Publicado"})

      {:ok, _} =
        Actions.run(PublishCourse, member_scope("institution_admin"), %{
          "course_id" => published.id
        })

      {conn, _student} = log_in_as(conn, "student")
      {:ok, view, _html} = live(conn, Paths.courses(institution()))

      assert has_element?(view, "#course-#{published.id}")
      refute has_element?(view, "#course-#{draft.id}")

      assert_raise AmautaWeb.ForbiddenError, fn ->
        live(conn, Paths.course(institution(), draft))
      end

      assert_raise AmautaWeb.ForbiddenError, fn -> live(conn, Paths.new_course(institution())) end
    end
  end

  describe "interior del curso" do
    test "muestra las pestañas fijas y el equipo docente", %{conn: conn} do
      course = create_course(%{"name" => "Programación I"})
      lead = user_fixture(first_name: "Marta", last_name: "Ríos")

      {:ok, _} =
        Amauta.Enrollments.enroll(institution(), course, lead.id, %{
          role: "course_lead",
          origin: "manual"
        })

      {conn, _admin} = log_in_as(conn, "institution_admin")

      {:ok, view, html} = live(conn, Paths.course(institution(), course))
      assert html =~ "Programación I"

      for tab <- [:content, :people, :grades, :settings] do
        assert has_element?(view, ~s(nav a[href="#{Paths.course(institution(), course, tab)}"]))
      end

      view
      |> element(~s(nav a[href="#{Paths.course(institution(), course, :people)}"]))
      |> render_click()

      assert has_element?(view, "#teaching", "Marta Ríos")
    end

    test "un estudiante no ve la pestaña de ajustes", %{conn: conn} do
      course = create_course(%{"name" => "Programación I"})

      {:ok, _} =
        Actions.run(PublishCourse, member_scope("institution_admin"), %{"course_id" => course.id})

      {conn, _student} = log_in_as(conn, "student", {"course", course.id})

      {:ok, view, _html} = live(conn, Paths.course(institution(), course))
      refute has_element?(view, ~s(a[href="#{Paths.course(institution(), course, :settings)}"]))
      refute has_element?(view, "#enrollment-code")

      assert_raise AmautaWeb.ForbiddenError, fn ->
        live(conn, Paths.course(institution(), course, :settings))
      end
    end

    test "ajustes: datos, opciones, código y estados", %{conn: conn} do
      course = create_course(%{"name" => "Programación I"})
      {conn, _admin} = log_in_as(conn, "institution_admin")

      {:ok, view, _html} = live(conn, Paths.course(institution(), course, :settings))

      view
      |> form("#settings_form",
        settings: %{feed_posting: "everyone", enrollment_code_enabled: "true"}
      )
      |> render_submit()

      updated = Courses.get(institution(), course.id)
      assert updated.settings.feed_posting == "everyone"
      assert has_element?(view, "#enrollment-code", updated.enrollment_code)

      view |> element(~s(button[phx-click="regenerate_code"])) |> render_click()
      refute Courses.get(institution(), course.id).enrollment_code == updated.enrollment_code

      view |> element(~s(button[phx-click="publish"])) |> render_click()
      assert Courses.get(institution(), course.id).status == "published"

      view |> element(~s(button[phx-click="archive"])) |> render_click()
      assert Courses.get(institution(), course.id).status == "archived"
      refute has_element?(view, "#settings_form")

      view |> element(~s(button[phx-click="reopen"])) |> render_click()

      assert {:error, {:live_redirect, %{to: _}}} =
               view |> form("#course_form", course: %{name: "Programación 1"}) |> render_submit()

      assert Courses.get(institution(), course.id).name == "Programación 1"
    end

    test "un slug inexistente es 404", %{conn: conn} do
      {conn, _admin} = log_in_as(conn, "institution_admin")

      assert_raise AmautaWeb.NotFoundError, fn ->
        live(conn, Paths.course(institution(), %{slug: "no-existe"}))
      end
    end
  end

  test "el trayecto muestra sus cursos por etapa", %{conn: conn} do
    {conn, admin} = log_in_as(conn, "institution_admin")
    scope = Amauta.Scope.for_user(institution(), admin)
    {:ok, pathway} = Actions.run(CreatePathway, scope, %{"name" => "Lic. en Sistemas"})

    {:ok, stage} =
      Actions.run(AddStage, scope, %{"pathway_id" => pathway.id, "name" => "1.er año"})

    create_course(%{
      "name" => "Programación I",
      "pathway_id" => pathway.id,
      "stage_id" => stage.id
    })

    create_course(%{"name" => "Inglés técnico", "pathway_id" => pathway.id})

    {:ok, view, _html} = live(conn, Paths.pathway(institution(), pathway))
    assert has_element?(view, "#stage-#{stage.id}", "Programación I")
    assert has_element?(view, "#courses-without-stage", "Inglés técnico")
  end
end
