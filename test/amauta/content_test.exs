defmodule Amauta.ContentTest do
  @moduledoc "Contenido: unidades, elementos, visibilidad, orden, archivos y permisos (RF-CON-001, 002, 004 y 005)."
  use Amauta.DataCase, async: true

  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Actions, Audit, Content, Enrollments, Scope, Storage}
  alias Amauta.Courses.Actions.{ArchiveCourse, CreateCourse, PublishCourse}
  alias Amauta.Files.Actions.{CompleteUpload, StartUpload}

  alias Amauta.Content.Actions.{
    CreateItem,
    CreateUnit,
    DeleteItem,
    DeleteUnit,
    MoveItem,
    MoveUnit,
    UpdateItem,
    UpdateUnit
  }

  setup do
    admin = member_scope("institution_admin")
    {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Programación I"})
    {:ok, course} = Actions.run(PublishCourse, admin, %{"course_id" => course.id})
    %{admin: admin, course: course, teacher: member(course, "teacher")}
  end

  defp member(course, role) do
    user = user_fixture()
    {:ok, _} = Enrollments.enroll(institution(), course, user.id, %{role: role, origin: "manual"})
    Scope.for_user(institution(), user)
  end

  defp unit(scope, course, title, attrs \\ %{}) do
    {:ok, unit} =
      Actions.run(
        CreateUnit,
        scope,
        Map.merge(%{"course_id" => course.id, "title" => title}, attrs)
      )

    unit
  end

  defp page(scope, unit, title, attrs \\ %{}) do
    {:ok, item} =
      Actions.run(
        CreateItem,
        scope,
        Map.merge(%{"unit_id" => unit.id, "kind" => "page", "title" => title}, attrs)
      )

    item
  end

  defp titles(units), do: Enum.map(units, &{&1.title, Enum.map(&1.items, fn i -> i.title end)})

  describe "unidades y elementos" do
    test "el equipo docente arma unidades con páginas, en orden", %{course: course, teacher: t} do
      u1 = unit(t, course, "Introducción")
      u2 = unit(t, course, "Variables")
      page(t, u1, "¿Qué es un algoritmo?")
      page(t, u1, "Diagramas de flujo")
      page(t, u2, "Tipos de datos")

      assert [
               {"Introducción", ["¿Qué es un algoritmo?", "Diagramas de flujo"]},
               {"Variables", ["Tipos de datos"]}
             ] = titles(Content.list_units(t, course))

      assert [%{action: "content.unit.create"} | _] =
               Audit.list_events(t) |> Enum.filter(&String.starts_with?(&1.action, "content."))
    end

    test "valida título, fechas y la fecha de lo programado", %{course: course, teacher: t} do
      assert {:error, changeset} =
               Actions.run(CreateUnit, t, %{
                 "course_id" => course.id,
                 "title" => "Unidad",
                 "starts_on" => "2027-04-10",
                 "ends_on" => "2027-04-01"
               })

      assert %{ends_on: [_]} = errors_on(changeset)

      assert {:error, changeset} =
               Actions.run(CreateUnit, t, %{
                 "course_id" => course.id,
                 "title" => "Unidad",
                 "visibility" => "scheduled"
               })

      assert %{publish_at: [_]} = errors_on(changeset)

      u = unit(t, course, "Unidad")

      assert {:error, changeset} =
               Actions.run(CreateItem, t, %{
                 "unit_id" => u.id,
                 "kind" => "material",
                 "title" => "Enlace",
                 "url" => "javascript:alert(1)"
               })

      assert %{url: [_]} = errors_on(changeset)
    end

    test "edita y borra", %{course: course, teacher: t} do
      u = unit(t, course, "Unidad")
      item = page(t, u, "Página")

      assert {:ok, %{title: "Unidad 1"}} =
               Actions.run(UpdateUnit, t, %{"unit_id" => u.id, "title" => "Unidad 1"})

      assert {:ok, %{title: "Página 1"}} =
               Actions.run(UpdateItem, t, %{"item_id" => item.id, "title" => "Página 1"})

      assert {:ok, _} = Actions.run(DeleteItem, t, %{"item_id" => item.id})
      assert [{"Unidad 1", []}] = titles(Content.list_units(t, course))

      assert {:ok, _} = Actions.run(DeleteUnit, t, %{"unit_id" => u.id})
      assert [] = Content.list_units(t, course)
    end
  end

  describe "orden" do
    test "mueve unidades y elementos, también a otra unidad", %{course: course, teacher: t} do
      u1 = unit(t, course, "Uno")
      u2 = unit(t, course, "Dos")
      a = page(t, u1, "A")
      _b = page(t, u1, "B")
      c = page(t, u2, "C")

      {:ok, _} = Actions.run(MoveUnit, t, %{"unit_id" => u2.id, "index" => 0})
      assert [{"Dos", ["C"]}, {"Uno", ["A", "B"]}] = titles(Content.list_units(t, course))

      # A pasa a la unidad Dos, entre... al principio.
      {:ok, _} = Actions.run(MoveItem, t, %{"item_id" => a.id, "unit_id" => u2.id, "index" => 0})
      assert [{"Dos", ["A", "C"]}, {"Uno", ["B"]}] = titles(Content.list_units(t, course))

      # Una posición fuera de rango queda al final.
      {:ok, _} = Actions.run(MoveItem, t, %{"item_id" => c.id, "unit_id" => u1.id, "index" => 99})
      assert [{"Dos", ["A"]}, {"Uno", ["B", "C"]}] = titles(Content.list_units(t, course))
    end

    test "no se mueve un elemento a una unidad de otro curso", %{
      admin: admin,
      course: course,
      teacher: t
    } do
      {:ok, other} = Actions.run(CreateCourse, admin, %{"name" => "Otro"})
      foreign = unit(admin, other, "Ajena")
      item = page(t, unit(t, course, "Propia"), "Página")

      assert {:error, :not_found} =
               Actions.run(MoveItem, t, %{
                 "item_id" => item.id,
                 "unit_id" => foreign.id,
                 "index" => 0
               })
    end
  end

  describe "visibilidad" do
    test "estudiantes no ven lo oculto ni lo programado a futuro", %{course: course, teacher: t} do
      student = member(course, "student")
      future = DateTime.add(DateTime.utc_now(), 3600)
      past = DateTime.add(DateTime.utc_now(), -3600)

      visible = unit(t, course, "Visible")
      unit(t, course, "Oculta", %{"visibility" => "hidden"})
      unit(t, course, "Más adelante", %{"visibility" => "scheduled", "publish_at" => future})
      unit(t, course, "Ya publicada", %{"visibility" => "scheduled", "publish_at" => past})

      page(t, visible, "Pública")
      hidden = page(t, visible, "Borrador", %{"visibility" => "hidden"})

      assert [{"Visible", ["Pública"]}, {"Ya publicada", []}] =
               titles(Content.list_units(student, course))

      assert length(Content.list_units(t, course)) == 4

      refute Content.get_item(student, course, hidden.id)
      assert Content.get_item(t, course, hidden.id)
    end

    test "un elemento visible de una unidad oculta tampoco se ve", %{course: course, teacher: t} do
      student = member(course, "student")
      u = unit(t, course, "Oculta", %{"visibility" => "hidden"})
      item = page(t, u, "Página")

      refute Content.get_item(student, course, item.id)
    end
  end

  describe "permisos" do
    test "estudiantes no gestionan contenido", %{course: course, teacher: t} do
      student = member(course, "student")
      u = unit(t, course, "Unidad")

      assert {:error, :forbidden} =
               Actions.run(CreateUnit, student, %{"course_id" => course.id, "title" => "X"})

      assert {:error, :forbidden} =
               Actions.run(CreateItem, student, %{
                 "unit_id" => u.id,
                 "kind" => "page",
                 "title" => "X"
               })

      assert {:error, :forbidden} = Actions.run(DeleteUnit, student, %{"unit_id" => u.id})
    end

    test "un curso archivado no se modifica", %{admin: admin, course: course, teacher: t} do
      u = unit(t, course, "Unidad")
      {:ok, _} = Actions.run(ArchiveCourse, admin, %{"course_id" => course.id})

      assert {:error, :forbidden} =
               Actions.run(UpdateUnit, t, %{"unit_id" => u.id, "title" => "Otra"})
    end
  end

  @pdf "%PDF-1.7\n" <> :binary.copy("x", 200)

  defp upload(scope, course, name \\ "apunte.pdf") do
    {:ok, %{file: file}} =
      Actions.run(StartUpload, scope, %{
        "purpose" => "content_material",
        "owner_id" => course.id,
        "filename" => name,
        "size" => byte_size(@pdf)
      })

    :ok = Storage.put(file.key, @pdf)
    {:ok, file} = Actions.run(CompleteUpload, scope, %{"file_id" => file.id})
    file
  end

  describe "materiales" do
    test "un material lleva archivos que ve quien ve el elemento", %{course: course, teacher: t} do
      student = member(course, "student")
      file = upload(t, course)
      u = unit(t, course, "Unidad")

      {:ok, item} =
        Actions.run(CreateItem, t, %{
          "unit_id" => u.id,
          "kind" => "material",
          "title" => "Apunte",
          "url" => "https://example.com/apunte",
          "file_ids" => [file.id]
        })

      assert [%{id: id}] = Content.files(t, item)
      assert id == file.id
      assert Amauta.Files.Purpose.can_view?(student, file)

      {:ok, _} = Actions.run(UpdateItem, t, %{"item_id" => item.id, "visibility" => "hidden"})
      refute Amauta.Files.Purpose.can_view?(student, file)

      # Quitar el archivo lo descarta.
      {:ok, _} = Actions.run(UpdateItem, t, %{"item_id" => item.id, "file_ids" => []})
      assert [] = Content.files(t, item)
      assert %{status: "rejected"} = Amauta.Files.get(t, file.id)
    end

    test "estudiantes no suben materiales", %{course: course} do
      student = member(course, "student")

      assert {:error, :forbidden} =
               Actions.run(StartUpload, student, %{
                 "purpose" => "content_material",
                 "owner_id" => course.id,
                 "filename" => "x.pdf",
                 "size" => 10
               })
    end

    test "no se adjunta un archivo de otra persona", %{course: course, teacher: t} do
      other = member(course, "teacher")
      file = upload(other, course)
      u = unit(t, course, "Unidad")

      assert {:error, :invalid_file} =
               Actions.run(CreateItem, t, %{
                 "unit_id" => u.id,
                 "kind" => "material",
                 "title" => "Ajeno",
                 "file_ids" => [file.id]
               })
    end
  end
end
