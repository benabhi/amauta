defmodule AmautaWeb.EnrollmentsLiveTest do
  @moduledoc "Pantallas de comisiones y matriculación: Personas del curso, CSV, código y trayecto."
  use AmautaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Actions, Enrollments}
  alias Amauta.Courses.Actions.{CreateCourse, PublishCourse, UpdateCourseSettings}
  alias Amauta.Enrollments.Actions.CreateSection
  alias Amauta.Pathways.Actions.CreatePathway
  alias AmautaWeb.Paths

  setup %{conn: conn} do
    admin_user = user_fixture()
    assign!(admin_user, "institution_admin", :institution)
    admin = Amauta.Scope.for_user(institution(), admin_user)
    {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Programación I"})
    %{conn: log_in_user(conn, admin_user), admin: admin, course: course}
  end

  defp section!(admin, course, name) do
    {:ok, section} =
      Actions.run(CreateSection, admin, %{"course_id" => course.id, "name" => name})

    section
  end

  describe "pestaña Personas" do
    test "crea una comisión y matricula a alguien en ella", %{conn: conn, course: course} do
      person = user_fixture(first_name: "Valentina", last_name: "Quispe")
      {:ok, view, _html} = live(conn, Paths.course(institution(), course, :people))

      view |> element(~s(button[phx-click="new_section"])) |> render_click()

      view
      |> form("#section_form", section: %{name: "Comisión A", schedule: "Lunes 8 a 10"})
      |> render_submit()

      [section] = Enrollments.list_sections(institution(), course)
      assert has_element?(view, "#section-#{section.id}", "Comisión A")

      view
      |> form("#enroll_form", enroll: %{q: "quispe", role: "student", section_id: section.id})
      |> render_change()

      view
      |> element(~s(#enroll_results [phx-click="enroll"][phx-value-id="#{person.id}"]))
      |> render_click()

      assert %{section_id: sid, role: "student"} =
               Enrollments.get_by_user(institution(), course, person.id)

      assert sid == section.id
      assert has_element?(view, "#students", "Valentina Quispe")
    end

    test "filtra por comisión, mueve, suspende y da de baja", ctx do
      %{conn: conn, admin: admin, course: course} = ctx
      a = section!(admin, course, "Comisión A")
      b = section!(admin, course, "Comisión B")
      ana = user_fixture(first_name: "Ana")
      beto = user_fixture(first_name: "Beto")

      {:ok, ea} =
        Enrollments.enroll(admin, course, ana.id, %{
          role: "student",
          origin: "manual",
          section_id: a.id
        })

      {:ok, eb} =
        Enrollments.enroll(admin, course, beto.id, %{
          role: "student",
          origin: "manual",
          section_id: b.id
        })

      {:ok, view, _html} =
        live(conn, Paths.course(institution(), course, :people, %{section: a.id}))

      assert has_element?(view, "#enrollment-#{ea.id}")
      refute has_element?(view, "#enrollment-#{eb.id}")

      view |> form("#section_selector", %{"section" => b.id}) |> render_change()
      assert_patch(view, Paths.course(institution(), course, :people, %{section: b.id}))
      assert has_element?(view, "#enrollment-#{eb.id}")

      view |> form("#move-#{eb.id}", %{"section_id" => a.id}) |> render_change()
      assert Enrollments.get(institution(), eb.id).section_id == a.id

      {:ok, view, _html} = live(conn, Paths.course(institution(), course, :people))
      view |> element(~s(#enrollment-#{ea.id} [phx-click="suspend_enrollment"])) |> render_click()
      assert Enrollments.get(institution(), ea.id).status == "suspended"

      view |> element(~s(#enrollment-#{ea.id} [phx-click="end_enrollment"])) |> render_click()
      assert Enrollments.get(institution(), ea.id).status == "ended"
      refute has_element?(view, "#enrollment-#{ea.id}")
    end

    test "un docente de comisión solo ve su comisión y no matricula", ctx do
      %{conn: conn, admin: admin, course: course} = ctx
      {:ok, _} = Actions.run(PublishCourse, admin, %{"course_id" => course.id})
      a = section!(admin, course, "Comisión A")
      b = section!(admin, course, "Comisión B")
      teacher = user_fixture()

      {:ok, _} =
        Enrollments.enroll(admin, course, teacher.id, %{
          role: "teacher",
          origin: "manual",
          section_id: a.id
        })

      other = user_fixture()

      {:ok, eb} =
        Enrollments.enroll(admin, course, other.id, %{
          role: "student",
          origin: "manual",
          section_id: b.id
        })

      conn = log_in_user(conn, teacher)

      {:ok, view, _html} =
        live(conn, Paths.course(institution(), course, :people, %{section: b.id}))

      refute has_element?(view, "#enrollment-#{eb.id}")
      refute has_element?(view, "#enroll_form")
      refute has_element?(view, ~s(#section_selector option[value="#{b.id}"]))
    end
  end

  test "matricula desde un CSV", %{conn: conn, course: course} do
    user_fixture(email: "ana@example.test")
    {:ok, view, _html} = live(conn, Paths.import_enrollments(institution(), course))

    csv = "email,rol\nana@example.test,estudiante\nnadie@example.test,\n"

    view
    |> file_input("#upload_form", :csv, [%{name: "matricula.csv", content: csv, type: "text/csv"}])
    |> render_upload("matricula.csv")

    view |> form("#upload_form") |> render_submit()
    assert has_element?(view, "#import_errors", "nadie@example.test")

    view |> element(~s(button[phx-click="apply"])) |> render_click()
    assert [%{origin: "csv"}] = Enrollments.list(institution(), course)
  end

  test "se suma con el código del curso", %{conn: conn, admin: admin, course: course} do
    {:ok, course} = Actions.run(PublishCourse, admin, %{"course_id" => course.id})

    {:ok, _} =
      Actions.run(UpdateCourseSettings, admin, %{
        "course_id" => course.id,
        "settings" => %{"enrollment_code_enabled" => "true"}
      })

    student = user_fixture()
    conn = log_in_user(conn, student)
    {:ok, view, _html} = live(conn, Paths.join(institution()))

    html = view |> form("#join_form", join: %{code: "NOEXISTE"}) |> render_submit()
    assert html =~ "That code doesn&#39;t work"

    assert {:error, {:live_redirect, %{to: to}}} =
             view |> form("#join_form", join: %{code: course.enrollment_code}) |> render_submit()

    assert to == Paths.course(institution(), course)
    assert %{role: "student"} = Enrollments.get_by_user(institution(), course, student.id)
  end

  test "matricula estudiantes desde el trayecto", %{conn: conn, admin: admin} do
    {:ok, pathway} = Actions.run(CreatePathway, admin, %{"name" => "Lic. en Sistemas"})

    {:ok, course} =
      Actions.run(CreateCourse, admin, %{"name" => "Redes", "pathway_id" => pathway.id})

    person = user_fixture(first_name: "Valentina", last_name: "Quispe")
    {:ok, view, _html} = live(conn, Paths.enroll_pathway(institution(), pathway))

    view
    |> form("#pathway_enroll_form", enroll: %{q: "quispe", propagation: "all"})
    |> render_change()

    view |> element(~s(#results [phx-click="add"][phx-value-id="#{person.id}"])) |> render_click()
    assert has_element?(view, "#selected", "Valentina Quispe")

    view |> element(~s(button[phx-click="submit"])) |> render_click()
    assert has_element?(view, "#enroll_result")
    assert %{origin: "pathway"} = Enrollments.get_by_user(institution(), course, person.id)
  end
end
