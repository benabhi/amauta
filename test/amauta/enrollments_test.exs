defmodule Amauta.EnrollmentsTest do
  @moduledoc "Comisiones y matrículas (RF-COM-001 a 003, RF-MAT-001 a 003, RF-TRA-003)."
  use Amauta.DataCase, async: true

  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Actions, Audit, Authorization, Enrollments, Scope}
  alias Amauta.Courses.Actions.{CreateCourse, PublishCourse, UpdateCourseSettings}
  alias Amauta.Enrollments.Enrollment
  alias Amauta.Enrollments.Import
  alias Amauta.Pathways.Actions.{AddStage, ArchivePathway, CreatePathway}

  alias Amauta.Enrollments.Actions.{
    CreateSection,
    DeleteSection,
    EndEnrollment,
    EnrollInPathway,
    EnrollUser,
    ImportEnrollments,
    JoinWithCode,
    UpdateEnrollment,
    UpdateSection
  }

  setup do
    admin = member_scope("institution_admin")
    {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Programación I"})

    {:ok, a} =
      Actions.run(CreateSection, admin, %{
        "course_id" => course.id,
        "name" => "Comisión A",
        "schedule" => "Lunes 8 a 10"
      })

    {:ok, b} =
      Actions.run(CreateSection, admin, %{"course_id" => course.id, "name" => "Comisión B"})

    %{admin: admin, course: course, a: a, b: b}
  end

  defp enroll(admin, course, user, role, section \\ nil) do
    Actions.run(EnrollUser, admin, %{
      "course_id" => course.id,
      "user_id" => user.id,
      "role" => role,
      "section_id" => section && section.id
    })
  end

  defp scope_of(user), do: Scope.for_user(institution(), user)

  describe "comisiones" do
    test "se crean, editan y validan nombres únicos", %{admin: admin, course: course, a: a} do
      assert [%{name: "Comisión A"}, %{name: "Comisión B"}] =
               Enrollments.list_sections(admin, course)

      assert {:error, changeset} =
               Actions.run(CreateSection, admin, %{
                 "course_id" => course.id,
                 "name" => "comisión a"
               })

      assert %{name: ["already exists"]} = errors_on(changeset)

      assert {:ok, %{room: "Aula 12", schedule: nil}} =
               Actions.run(UpdateSection, admin, %{
                 "section_id" => a.id,
                 "room" => "Aula 12",
                 "schedule" => ""
               })
    end

    test "borrar una comisión no da de baja a nadie", %{admin: admin, course: course, a: a} do
      student = user_fixture()
      teacher = user_fixture()
      {:ok, _} = enroll(admin, course, student, "student", a)
      {:ok, _} = enroll(admin, course, teacher, "teacher", a)

      {:ok, _} = Actions.run(DeleteSection, admin, %{"section_id" => a.id})

      assert [%{section_id: nil, status: "active"}, %{section_id: nil, status: "active"}] =
               Enrollments.list(admin, course)

      # El docente pasa a tener su rol en todo el curso.
      assert Authorization.can?(scope_of(teacher), "course.content.manage", course)
    end
  end

  describe "matrícula" do
    test "matricula, queda auditada y da los permisos del rol", ctx do
      %{admin: admin, course: course} = ctx
      student = user_fixture()

      assert {:ok, %Enrollment{status: "active", origin: "manual", role: "student"}} =
               enroll(admin, course, student, "student")

      assert Authorization.can?(scope_of(student), "course.submissions.create_own", course)
      assert "enrollments.enrollment.create" in Enum.map(Audit.list_events(admin), & &1.action)
    end

    test "no se matricula dos veces", %{admin: admin, course: course} do
      student = user_fixture()
      {:ok, _} = enroll(admin, course, student, "student")

      assert {:error, changeset} = enroll(admin, course, student, "teacher")
      assert %{user_id: ["already enrolled"]} = errors_on(changeset)
    end

    test "la comisión tiene que ser del curso", %{admin: admin} do
      {:ok, other} = Actions.run(CreateCourse, admin, %{"name" => "Álgebra"})

      {:ok, section} =
        Actions.run(CreateSection, admin, %{"course_id" => other.id, "name" => "X"})

      {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Física"})

      assert {:error, changeset} =
               Enrollments.enroll(admin, course, user_fixture().id, %{
                 role: "student",
                 origin: "manual",
                 section_id: section.id
               })

      assert %{section_id: ["does not belong to the course"]} = errors_on(changeset)
    end

    test "suspender quita el acceso; dar de baja conserva la matrícula", ctx do
      %{admin: admin, course: course} = ctx
      student = user_fixture()
      {:ok, enrollment} = enroll(admin, course, student, "student")

      {:ok, %{status: "suspended"}} =
        Actions.run(UpdateEnrollment, admin, %{
          "enrollment_id" => enrollment.id,
          "status" => "suspended"
        })

      refute Authorization.can?(scope_of(student), "course.view", course)

      {:ok, %{status: "active"}} =
        Actions.run(UpdateEnrollment, admin, %{
          "enrollment_id" => enrollment.id,
          "status" => "active"
        })

      assert Authorization.can?(scope_of(student), "course.view", course)

      {:ok, %{status: "ended", ended_at: %DateTime{}}} =
        Actions.run(EndEnrollment, admin, %{"enrollment_id" => enrollment.id})

      refute Authorization.can?(scope_of(student), "course.view", course)
      assert [%{status: "ended"}] = Enrollments.list(admin, course, %{"status" => "ended"})
      assert [] = Enrollments.list(admin, course)

      # Se puede volver a matricular: la misma matrícula se reactiva.
      assert {:ok, %{id: id, status: "active"}} = enroll(admin, course, student, "student")
      assert id == enrollment.id
    end

    test "cambiar de comisión mueve el permiso del docente", ctx do
      %{admin: admin, course: course, a: a, b: b} = ctx
      teacher = user_fixture()
      {:ok, enrollment} = enroll(admin, course, teacher, "teacher", a)

      section_a = %{a | course: course}
      section_b = %{b | course: course}
      assert Authorization.can?(scope_of(teacher), "course.submissions.grade", section_a)
      refute Authorization.can?(scope_of(teacher), "course.submissions.grade", section_b)
      refute Authorization.can?(scope_of(teacher), "course.submissions.grade", course)

      {:ok, _} =
        Actions.run(UpdateEnrollment, admin, %{
          "enrollment_id" => enrollment.id,
          "section_id" => b.id
        })

      assert Authorization.can?(scope_of(teacher), "course.submissions.grade", section_b)
      refute Authorization.can?(scope_of(teacher), "course.submissions.grade", section_a)
    end

    test "un docente de comisión entra al curso y está limitado a su comisión", ctx do
      %{admin: admin, course: course, a: a} = ctx
      teacher = user_fixture()
      {:ok, _} = enroll(admin, course, teacher, "teacher", a)
      scope = scope_of(teacher)

      assert Enrollments.can_in_course?(scope, "course.view", course)
      assert [%{id: id}] = Enrollments.own_sections(scope, course)
      assert id == a.id
      assert [%{id: course_id}] = Amauta.Courses.list_visible(scope)
      assert course_id == course.id
    end

    test "participantes: equipo docente ordenado por rol y estudiantes", ctx do
      %{admin: admin, course: course, a: a} = ctx
      {:ok, _} = enroll(admin, course, user_fixture(), "teacher")
      {:ok, _} = enroll(admin, course, user_fixture(), "course_lead")
      {:ok, _} = enroll(admin, course, user_fixture(), "student", a)
      {:ok, _} = enroll(admin, course, user_fixture(), "student")

      assert {[%{role: "course_lead"}, %{role: "teacher"}], [_, _]} =
               Enrollments.participants(admin, course)

      assert {_, [%{section_id: section_id}]} =
               Enrollments.participants(admin, course, %{"section" => a.id})

      assert section_id == a.id

      assert {_, [%{section_id: nil}]} =
               Enrollments.participants(admin, course, %{"section" => "none"})
    end
  end

  describe "CSV" do
    test "simula, informa errores y aplica", %{admin: admin, course: course} do
      ana = user_fixture(email: "ana@example.test")
      beto = user_fixture(email: "beto@example.test")
      carla = user_fixture(email: "carla@example.test")
      {:ok, _} = enroll(admin, course, carla, "student")

      csv = """
      Email;Rol;Comisión
      ANA@example.test;estudiante;comision a
      beto@example.test;docente;
      carla@example.test;;
      nadie@example.test;;
      ana@example.test;;
      beto2@example.test;mago;Comisión Z
      """

      {:ok, parsed} = Import.parse(csv)
      {:ok, plan} = Import.plan(admin, course, parsed)

      assert %{enroll: 2, already: 1, error: 3} = Import.summary(plan)
      assert [%{errors: [:unknown_user]}] = Enum.filter(plan, &(&1.email == "nadie@example.test"))
      assert %{errors: [:repeated]} = Enum.at(plan, 4)
      assert %{errors: [:unknown_user, :unknown_role, :unknown_section]} = Enum.at(plan, 5)

      rows = Import.rows_to_apply(plan)

      assert {:ok, %{enrolled: 2, skipped: 0}} =
               Actions.run(ImportEnrollments, admin, %{"course_id" => course.id, "rows" => rows})

      assert %{role: "student", origin: "csv", section_id: section_id} =
               Enrollments.get_by_user(admin, course, ana.id)

      refute is_nil(section_id)
      assert %{role: "teacher"} = Enrollments.get_by_user(admin, course, beto.id)
    end

    test "sin columna de email no hay plan", %{admin: admin, course: course} do
      {:ok, parsed} = Import.parse("nombre,apellido\nAna,Pérez\n")
      assert {:error, :no_email} = Import.plan(admin, course, parsed)
    end
  end

  describe "código de inscripción" do
    setup %{admin: admin, course: course} do
      {:ok, course} = Actions.run(PublishCourse, admin, %{"course_id" => course.id})
      %{course: course}
    end

    test "solo funciona si está habilitado", %{admin: admin, course: course} do
      student = scope_of(user_fixture())
      code = String.downcase(course.enrollment_code)

      assert {:error, :invalid_code} = Actions.run(JoinWithCode, student, %{"code" => code})

      {:ok, _} =
        Actions.run(UpdateCourseSettings, admin, %{
          "course_id" => course.id,
          "settings" => %{"enrollment_code_enabled" => "true"}
        })

      assert {:ok, %{id: id}} = Actions.run(JoinWithCode, student, %{"code" => " #{code} "})
      assert id == course.id

      assert %{role: "student", origin: "code", section_id: nil} =
               Enrollments.get_by_user(admin, course, student.user.id)

      # Volver a usarlo no duplica nada.
      assert {:ok, _} = Actions.run(JoinWithCode, student, %{"code" => code})
    end

    test "una matrícula suspendida no se levanta con el código", %{admin: admin, course: course} do
      {:ok, _} =
        Actions.run(UpdateCourseSettings, admin, %{
          "course_id" => course.id,
          "settings" => %{"enrollment_code_enabled" => "true"}
        })

      user = user_fixture()
      {:ok, enrollment} = enroll(admin, course, user, "student")

      {:ok, _} =
        Actions.run(UpdateEnrollment, admin, %{
          "enrollment_id" => enrollment.id,
          "status" => "suspended"
        })

      assert {:error, :suspended} =
               Actions.run(JoinWithCode, scope_of(user), %{"code" => course.enrollment_code})
    end
  end

  describe "trayecto" do
    test "matricula en todos, en los obligatorios o en los de una etapa", %{admin: admin} do
      {:ok, pathway} = Actions.run(CreatePathway, admin, %{"name" => "Lic. en Sistemas"})
      {:ok, s1} = Actions.run(AddStage, admin, %{"pathway_id" => pathway.id, "name" => "1"})
      {:ok, s2} = Actions.run(AddStage, admin, %{"pathway_id" => pathway.id, "name" => "2"})

      create = fn name, stage, required ->
        {:ok, c} =
          Actions.run(CreateCourse, admin, %{
            "name" => name,
            "pathway_id" => pathway.id,
            "stage_id" => stage.id,
            "required" => required
          })

        c
      end

      prog = create.("Prog", s1, "true")
      taller = create.("Taller", s1, "false")
      redes = create.("Redes", s2, "true")
      [ana, beto, carla] = for _ <- 1..3, do: user_fixture()

      run = fn users, propagation, extra ->
        Actions.run(
          EnrollInPathway,
          admin,
          Map.merge(
            %{
              "pathway_id" => pathway.id,
              "user_ids" => Enum.map(users, & &1.id),
              "propagation" => propagation
            },
            extra
          )
        )
      end

      assert {:ok, %{courses: 3, enrolled: 3}} = run.([ana], "all", %{})
      assert {:ok, %{courses: 2, enrolled: 2}} = run.([beto], "required", %{})
      assert {:ok, %{courses: 2, enrolled: 2}} = run.([carla], "stage", %{"stage_id" => s1.id})

      # Repetir no duplica.
      assert {:ok, %{enrolled: 0, skipped: 3}} = run.([ana], "all", %{})

      assert %{origin: "pathway"} = Enrollments.get_by_user(admin, prog, beto.id)
      assert is_nil(Enrollments.get_by_user(admin, taller, beto.id))
      assert is_nil(Enrollments.get_by_user(admin, redes, carla.id))

      assert {:error, changeset} = run.([ana], "stage", %{})
      assert %{stage_id: ["can't be blank"]} = errors_on(changeset)

      {:ok, _} = Actions.run(ArchivePathway, admin, %{"pathway_id" => pathway.id})
      assert {:error, :archived} = run.([ana], "all", %{})
    end
  end

  describe "matriz rol × acción" do
    # {rol, gestionar comisiones, matricular estudiantes, matricular docentes}
    @matrix [
      {"institution_admin", true, true, true},
      {"academic_management", true, true, false},
      {"pathway_coordinator", true, true, true},
      {"course_lead", true, false, false},
      {"teacher", false, false, false},
      {"student", false, false, false}
    ]

    for {role, sections, students, teachers} <- @matrix do
      test role, %{course: course} do
        scope = member_scope(unquote(role))

        expect = fn allowed, result ->
          if allowed,
            do: assert({:ok, _} = result),
            else: assert({:error, :forbidden} = result)
        end

        expect.(
          unquote(sections),
          Actions.run(CreateSection, scope, %{"course_id" => course.id, "name" => "Nueva"})
        )

        expect.(unquote(students), enroll(scope, course, user_fixture(), "student"))
        expect.(unquote(teachers), enroll(scope, course, user_fixture(), "teacher"))
      end
    end
  end

  test "las matrículas de una institución no se ven desde otra", %{admin: admin, course: course} do
    {:ok, _} = enroll(admin, course, user_fixture(), "student")
    b = Amauta.Fixtures.institution_fixture("inst_test_b")

    assert [_] = Enrollments.list(admin, course)
    assert [] = Amauta.Repo.all(Enrollment, Amauta.Tenancy.opts(b))
  end
end
