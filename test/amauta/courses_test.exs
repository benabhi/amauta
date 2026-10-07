defmodule Amauta.CoursesTest do
  @moduledoc "Cursos: datos, trayecto y etapa, estados y ajustes (RF-CUR-001, 005 y 007)."
  use Amauta.DataCase, async: true

  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Actions, Audit, Authorization, Courses, Periods, Scope}
  alias Amauta.Courses.Course
  alias Amauta.Pathways.Actions.{AddStage, CreatePathway}

  alias Amauta.Courses.Actions.{
    ArchiveCourse,
    CreateCourse,
    PublishCourse,
    RegenerateEnrollmentCode,
    ReopenCourse,
    UpdateCourse,
    UpdateCourseSettings
  }

  setup do
    admin = member_scope("institution_admin")
    {:ok, pathway} = Actions.run(CreatePathway, admin, %{"name" => "Lic. en Sistemas"})

    {:ok, stage} =
      Actions.run(AddStage, admin, %{"pathway_id" => pathway.id, "name" => "1.er año"})

    {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Programación I"})
    %{admin: admin, pathway: pathway, stage: stage, course: course}
  end

  describe "alta" do
    test "valores por defecto: borrador, slug, código e ícono", %{admin: admin, course: course} do
      assert %Course{status: "draft", slug: "programacion-i", icon: "book-open"} = course
      assert course.enrollment_code =~ ~r/^[A-HJ-NP-Z2-9]{7}$/
      assert course.settings.feed_posting == "teachers"
      refute course.settings.enrollment_code_enabled
      assert [%{action: "courses.course.create"} | _] = Enum.reverse(Audit.list_events(admin))
    end

    test "sin período usa el actual", %{admin: admin} do
      {:ok, period} =
        Periods.create(admin, %{
          name: "2027 · 1C",
          starts_on: ~D[2027-03-01],
          ends_on: ~D[2027-07-15]
        })

      {:ok, _} = Periods.set_current(admin, period)

      {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Álgebra"})
      assert course.period_id == period.id
    end

    test "dentro de un trayecto, en una etapa y como optativo", ctx do
      %{admin: admin, pathway: pathway, stage: stage} = ctx

      {:ok, course} =
        Actions.run(CreateCourse, admin, %{
          "name" => "Taller de Linux",
          "pathway_id" => pathway.id,
          "stage_id" => stage.id,
          "required" => "false"
        })

      assert %{pathway_id: pid, stage_id: sid, required: false} = course
      assert {pid, sid} == {pathway.id, stage.id}
      assert %{^sid => [%{id: id}]} = Courses.by_stage(admin, pathway)
      assert id == course.id
    end

    test "la etapa tiene que ser del trayecto", %{admin: admin, stage: stage} do
      {:ok, other} = Actions.run(CreatePathway, admin, %{"name" => "Otro"})

      assert {:error, changeset} =
               Actions.run(CreateCourse, admin, %{
                 "name" => "X",
                 "pathway_id" => other.id,
                 "stage_id" => stage.id
               })

      assert %{stage_id: ["does not belong to the pathway"]} = errors_on(changeset)

      # Sin trayecto, la etapa se descarta.
      {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Y", "stage_id" => stage.id})
      assert is_nil(course.stage_id)
    end
  end

  describe "edición" do
    test "edita y saca el curso del trayecto", %{admin: admin, pathway: pathway} do
      {:ok, course} =
        Actions.run(CreateCourse, admin, %{"name" => "Redes", "pathway_id" => pathway.id})

      assert {:ok, %{pathway_id: nil, name: "Redes I"}} =
               Actions.run(UpdateCourse, admin, %{
                 "course_id" => course.id,
                 "name" => "Redes I",
                 "pathway_id" => ""
               })
    end

    test "cambia los ajustes y valida sus valores", %{admin: admin, course: course} do
      assert {:ok, %{settings: %{feed_posting: "moderated", enrollment_code_enabled: true}}} =
               Actions.run(UpdateCourseSettings, admin, %{
                 "course_id" => course.id,
                 "settings" => %{
                   "feed_posting" => "moderated",
                   "enrollment_code_enabled" => "true"
                 }
               })

      assert {:error, changeset} =
               Actions.run(UpdateCourseSettings, admin, %{
                 "course_id" => course.id,
                 "settings" => %{"grading_scale" => "letters"}
               })

      assert %{settings: %{grading_scale: ["is invalid"]}} = errors_on(changeset)
    end

    test "genera un código de inscripción nuevo", %{admin: admin, course: course} do
      {:ok, updated} = Actions.run(RegenerateEnrollmentCode, admin, %{"course_id" => course.id})
      assert updated.enrollment_code != course.enrollment_code
    end

    test "borrador → publicado → archivado (solo lectura) → publicado", ctx do
      %{admin: admin, course: course} = ctx
      params = %{"course_id" => course.id}

      assert {:error, :invalid_transition} = Actions.run(ReopenCourse, admin, params)
      assert {:ok, %{status: "published"}} = Actions.run(PublishCourse, admin, params)
      assert {:ok, %{status: "archived"}} = Actions.run(ArchiveCourse, admin, params)

      assert {:error, :archived} =
               Actions.run(UpdateCourse, admin, Map.put(params, "name", "Otro"))

      assert {:error, :archived} = Actions.run(RegenerateEnrollmentCode, admin, params)
      assert {:ok, %{status: "published"}} = Actions.run(ReopenCourse, admin, params)
    end
  end

  describe "visibilidad" do
    test "la lista oculta los archivados y filtra por período y texto", ctx do
      %{admin: admin, course: course} = ctx
      {:ok, other} = Actions.run(CreateCourse, admin, %{"name" => "Álgebra", "code" => "ALG"})
      {:ok, _} = Actions.run(ArchiveCourse, admin, %{"course_id" => course.id})

      assert [%{id: id}] = Courses.list_visible(admin)
      assert id == other.id
      assert [_] = Courses.list_visible(admin, %{"q" => "alg"})
      assert [_] = Courses.list_visible(admin, %{"status" => "archived"})
      assert [] = Courses.list_visible(admin, %{"period_id" => Ecto.UUID.generate()})
    end

    test "con un rol en el curso o en su trayecto se ve; si no, no", ctx do
      %{admin: admin, pathway: pathway, course: course} = ctx

      {:ok, in_pathway} =
        Actions.run(CreateCourse, admin, %{"name" => "Sistemas I", "pathway_id" => pathway.id})

      teacher = user_fixture()
      assign!(teacher, "teacher", {"course", course.id})
      coordinator = user_fixture()
      assign!(coordinator, "pathway_coordinator", {"pathway", pathway.id})

      assert [%{id: a}] = Courses.list_visible(Scope.for_user(institution(), teacher))
      assert a == course.id
      assert [%{id: b}] = Courses.list_visible(Scope.for_user(institution(), coordinator))
      assert b == in_pathway.id
    end
  end

  describe "matriz rol × acción" do
    # {rol, crear suelto, editar, archivar}
    @matrix [
      {"institution_admin", true, true, true},
      {"academic_management", false, false, false},
      {"pathway_coordinator", true, true, true},
      {"course_lead", false, true, true},
      {"teacher", false, false, false},
      {"assistant", false, false, false},
      {"student", false, false, false},
      {"observer", false, false, false}
    ]

    for {role, create, update, archive} <- @matrix do
      test role, %{course: course} do
        scope = member_scope(unquote(role))
        params = %{"course_id" => course.id}

        expect = fn allowed, result ->
          if allowed,
            do: assert({:ok, _} = result),
            else: assert({:error, :forbidden} = result)
        end

        expect.(unquote(create), Actions.run(CreateCourse, scope, %{"name" => "Nuevo"}))
        expect.(unquote(update), Actions.run(UpdateCourse, scope, Map.put(params, "name", "X")))
        expect.(unquote(update), Actions.run(PublishCourse, scope, params))
        expect.(unquote(archive), Actions.run(ArchiveCourse, scope, params))
      end
    end

    test "la coordinación de un trayecto crea cursos en el suyo y no sueltos", ctx do
      %{admin: admin, pathway: pathway} = ctx
      {:ok, other} = Actions.run(CreatePathway, admin, %{"name" => "Otro"})
      coordinator = member_scope("pathway_coordinator", {"pathway", pathway.id})

      assert {:ok, course} =
               Actions.run(CreateCourse, coordinator, %{"name" => "A", "pathway_id" => pathway.id})

      assert {:error, :forbidden} = Actions.run(CreateCourse, coordinator, %{"name" => "B"})

      assert {:error, :forbidden} =
               Actions.run(CreateCourse, coordinator, %{"name" => "C", "pathway_id" => other.id})

      # Tampoco puede llevarse el curso a un trayecto ajeno.
      assert {:error, :forbidden} =
               Actions.run(UpdateCourse, coordinator, %{
                 "course_id" => course.id,
                 "pathway_id" => other.id
               })
    end

    test "un rol en el trayecto aplica a sus cursos", %{admin: admin, pathway: pathway} do
      {:ok, course} =
        Actions.run(CreateCourse, admin, %{"name" => "A", "pathway_id" => pathway.id})

      coordinator = member_scope("pathway_coordinator", {"pathway", pathway.id})

      assert Authorization.can?(coordinator, "course.update", course)
    end
  end

  test "los cursos de una institución no se ven desde otra", %{admin: admin} do
    b = Amauta.Fixtures.institution_fixture("inst_test_b")

    assert [_] = Courses.list_visible(admin)
    assert is_nil(Courses.get_by_slug(b, "programacion-i"))
    assert [] = Amauta.Repo.all(Course, Amauta.Tenancy.opts(b))
  end
end
