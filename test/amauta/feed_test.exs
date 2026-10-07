defmodule Amauta.FeedTest do
  @moduledoc "Tablón: publicar, borradores, destinatarios, visibilidad y permisos (RF-TAB-001 a 003, 007 y 008)."
  use Amauta.DataCase, async: true

  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Actions, Audit, Enrollments, Feed, Scope}
  alias Amauta.Courses.Actions.{CreateCourse, PublishCourse, UpdateCourseSettings}
  alias Amauta.Enrollments.Actions.CreateSection
  alias Amauta.Feed.Actions.{DeletePost, PublishPost, SaveDraft, UpdatePost}

  setup do
    admin = member_scope("institution_admin")
    {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Programación I"})
    {:ok, course} = Actions.run(PublishCourse, admin, %{"course_id" => course.id})
    {:ok, a} = Actions.run(CreateSection, admin, %{"course_id" => course.id, "name" => "A"})
    {:ok, b} = Actions.run(CreateSection, admin, %{"course_id" => course.id, "name" => "B"})
    %{admin: admin, course: course, a: a, b: b}
  end

  defp body(text),
    do:
      Jason.encode!(%{
        "type" => "doc",
        "content" => [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}
        ]
      })

  defp member(course, role, section \\ nil) do
    user = user_fixture()

    {:ok, _} =
      Enrollments.enroll(institution(), course, user.id, %{
        role: role,
        origin: "manual",
        section_id: section && section.id
      })

    Scope.for_user(institution(), user)
  end

  defp publish(scope, course, text, section \\ nil) do
    Actions.run(PublishPost, scope, %{
      "course_id" => course.id,
      "body" => body(text),
      "section_id" => section && section.id
    })
  end

  defp texts(scope, course, filters \\ %{}) do
    scope |> Feed.list_posts(course, filters) |> Enum.map(&Amauta.RichText.to_text(&1.body))
  end

  describe "publicar" do
    test "el equipo docente publica, se audita y se avisa en tiempo real", %{course: course} do
      teacher = member(course, "teacher")
      Phoenix.PubSub.subscribe(Amauta.PubSub, Feed.topic(course))

      assert {:ok, post} = publish(teacher, course, "Bienvenidos")
      assert post.status == "published" and post.published_at
      assert_received {:feed, :published, %{id: id}}
      assert id == post.id
      assert "feed.post.publish" in Enum.map(Audit.list_events(teacher), & &1.action)
    end

    test "no se publica vacío", %{course: course} do
      teacher = member(course, "teacher")

      assert {:error, changeset} =
               Actions.run(PublishPost, teacher, %{"course_id" => course.id, "body" => ""})

      assert %{body: ["write something first"]} = errors_on(changeset)
    end

    test "el borrador se guarda mientras se escribe y es el que se publica", %{course: course} do
      teacher = member(course, "teacher")

      {:ok, draft} =
        Actions.run(SaveDraft, teacher, %{"course_id" => course.id, "body" => body("Hol")})

      {:ok, same} =
        Actions.run(SaveDraft, teacher, %{"course_id" => course.id, "body" => body("Hola")})

      assert same.id == draft.id
      assert [] = Feed.list_posts(teacher, course)

      {:ok, post} = publish(teacher, course, "Hola a todos")
      assert post.id == draft.id
      assert is_nil(Feed.get_draft(teacher, course))
    end

    test "editar deja la marca y solo lo hace el autor", %{course: course} do
      teacher = member(course, "teacher")
      other = member(course, "teacher")
      {:ok, post} = publish(teacher, course, "Clase el lunes")

      assert {:error, :forbidden} =
               Actions.run(UpdatePost, other, %{"post_id" => post.id, "body" => body("x")})

      assert {:ok, %{edited_at: %DateTime{}}} =
               Actions.run(UpdatePost, teacher, %{
                 "post_id" => post.id,
                 "body" => body("Clase el martes")
               })

      assert texts(teacher, course) == ["Clase el martes"]
    end

    test "elimina el autor o quien modera", %{course: course} do
      teacher = member(course, "teacher")
      student = member(course, "student")
      {:ok, mine} = publish(teacher, course, "Uno")
      {:ok, other} = publish(teacher, course, "Dos")

      assert {:error, :forbidden} = Actions.run(DeletePost, student, %{"post_id" => mine.id})
      assert {:ok, _} = Actions.run(DeletePost, teacher, %{"post_id" => mine.id})

      lead = member(course, "course_lead")
      assert {:ok, _} = Actions.run(DeletePost, lead, %{"post_id" => other.id})
      assert [] = Feed.list_posts(teacher, course)
    end
  end

  describe "quién publica" do
    test "estudiantes solo si el curso permite que publiquen todos", %{
      admin: admin,
      course: course
    } do
      student = member(course, "student")
      assert {:error, :forbidden} = publish(student, course, "Hola")

      set = fn value ->
        Actions.run(UpdateCourseSettings, admin, %{
          "course_id" => course.id,
          "settings" => %{"feed_posting" => value}
        })
      end

      {:ok, _} = set.("moderated")
      assert {:error, :forbidden} = publish(member(course, "student"), course, "Hola")

      {:ok, _} = set.("everyone")
      assert {:ok, _} = publish(member(course, "student"), course, "Hola")
    end

    test "un estudiante no publica en otra comisión", %{admin: admin, course: course, a: a, b: b} do
      {:ok, _} =
        Actions.run(UpdateCourseSettings, admin, %{
          "course_id" => course.id,
          "settings" => %{"feed_posting" => "everyone"}
        })

      student = member(course, "student", a)
      assert {:ok, _} = publish(student, course, "Para A", a)
      assert {:ok, _} = publish(student, course, "Para todos")
      assert {:error, :forbidden} = publish(student, course, "Para B", b)
    end

    test "un docente de comisión publica solo para la suya", %{course: course, a: a, b: b} do
      teacher = member(course, "teacher", a)
      assert {:ok, _} = publish(teacher, course, "Para A", a)
      assert {:error, :forbidden} = publish(teacher, course, "Para B", b)
      assert {:error, :forbidden} = publish(teacher, course, "Para todos")
    end

    test "en un curso archivado no se publica", %{admin: admin, course: course} do
      teacher = member(course, "teacher")

      {:ok, _} =
        Actions.run(Amauta.Courses.Actions.ArchiveCourse, admin, %{"course_id" => course.id})

      assert {:error, _} = publish(teacher, Amauta.Courses.get(admin, course.id), "Hola")
    end
  end

  describe "visibilidad" do
    test "cada quien ve lo del curso y lo de su comisión; el equipo docente, todo", ctx do
      %{course: course, a: a, b: b} = ctx
      lead = member(course, "course_lead")
      {:ok, _} = publish(lead, course, "Para todos")
      {:ok, _} = publish(lead, course, "Para A", a)
      {:ok, _} = publish(lead, course, "Para B", b)

      assert Enum.sort(texts(lead, course)) == ["Para A", "Para B", "Para todos"]
      assert Enum.sort(texts(member(course, "student", a), course)) == ["Para A", "Para todos"]
      assert texts(member(course, "student"), course) == ["Para todos"]
      assert Enum.sort(texts(member(course, "teacher", b), course)) == ["Para B", "Para todos"]

      # El filtro de comisión del encabezado.
      assert Enum.sort(texts(lead, course, %{"section" => a.id})) == ["Para A", "Para todos"]
    end

    test "las publicaciones de un curso no se ven desde otra institución", %{course: course} do
      {:ok, _} = publish(member(course, "teacher"), course, "Hola")
      b = Amauta.Fixtures.institution_fixture("inst_test_b")
      assert [] = Amauta.Repo.all(Amauta.Feed.Post, Amauta.Tenancy.opts(b))
    end
  end
end
