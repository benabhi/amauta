defmodule Amauta.FeedAttachmentsTest do
  @moduledoc "Adjuntos del tablón (RF-TAB-005): subir, vincular, ver, quitar y borrar."
  use Amauta.DataCase, async: true

  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Actions, Enrollments, Feed, Files, Scope, Storage}
  alias Amauta.Courses.Actions.{CreateCourse, PublishCourse, UpdateCourseSettings}
  alias Amauta.Enrollments.Actions.CreateSection
  alias Amauta.Feed.Actions.{DeletePost, PublishPost, ReplyToPost, SaveDraft, UpdatePost}
  alias Amauta.Files.Actions.{CompleteUpload, StartUpload}
  alias Amauta.Files.Purpose

  @pdf "%PDF-1.7\n" <> :binary.copy("x", 200)

  setup do
    admin = member_scope("institution_admin")
    {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Programación I"})
    {:ok, course} = Actions.run(PublishCourse, admin, %{"course_id" => course.id})
    {:ok, b} = Actions.run(CreateSection, admin, %{"course_id" => course.id, "name" => "B"})
    %{admin: admin, course: course, b: b}
  end

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

  defp body(text),
    do:
      Jason.encode!(%{
        "type" => "doc",
        "content" => [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}
        ]
      })

  # Sube un PDF para el tablón del curso, como lo haría el navegador.
  defp upload(scope, course, name \\ "apunte.pdf") do
    with {:ok, %{file: file}} <-
           Actions.run(StartUpload, scope, %{
             "purpose" => "feed_attachment",
             "owner_id" => course.id,
             "filename" => name,
             "size" => byte_size(@pdf)
           }) do
      :ok = Storage.put(file.key, @pdf)
      Actions.run(CompleteUpload, scope, %{"file_id" => file.id})
    end
  end

  defp publish(scope, course, files, section \\ nil) do
    Actions.run(PublishPost, scope, %{
      "course_id" => course.id,
      "body" => body("Material"),
      "section_id" => section && section.id,
      "attachment_ids" => Enum.map(files, & &1.id)
    })
  end

  defp attached(scope, course, post) do
    scope
    |> Feed.get_visible(course, post.id)
    |> Map.fetch!(:attachments)
    |> Enum.map(& &1.file.filename)
  end

  test "el equipo docente adjunta archivos al publicar, en orden", %{course: course} do
    teacher = member(course, "teacher")
    {:ok, one} = upload(teacher, course, "programa.pdf")
    {:ok, two} = upload(teacher, course, "cronograma.pdf")

    assert {:ok, post} = publish(teacher, course, [two, one])
    assert attached(teacher, course, post) == ["cronograma.pdf", "programa.pdf"]
  end

  test "lo ven quienes ven la publicación; nadie más", %{course: course, b: b} do
    teacher = member(course, "teacher")
    {:ok, file} = upload(teacher, course)
    {:ok, _} = publish(teacher, course, [file], b)

    assert Purpose.can_view?(member(course, "student", b), file)
    refute Purpose.can_view?(member(course, "student"), file)

    # Alguien de la institución que no está en el curso.
    refute Purpose.can_view?(Scope.for_user(institution(), user_fixture()), file)
  end

  test "quien lo subió lo ve antes de publicar", %{course: course} do
    teacher = member(course, "teacher")
    {:ok, file} = upload(teacher, course)

    assert Purpose.can_view?(teacher, file)
    refute Purpose.can_view?(member(course, "teacher"), file)
  end

  test "los estudiantes adjuntan al responder, si el curso lo permite", ctx do
    %{admin: admin, course: course} = ctx
    teacher = member(course, "teacher")
    student = member(course, "student")
    {:ok, post} = publish(teacher, course, [])

    {:ok, file} = upload(student, course, "consulta.pdf")

    assert {:ok, reply} =
             Actions.run(ReplyToPost, student, %{
               "post_id" => post.id,
               "body" => body("Adjunto mi duda"),
               "attachment_ids" => [file.id]
             })

    [shown] = Feed.get_visible(teacher, course, post.id).replies
    assert shown.id == reply.id
    assert [%{file: %{filename: "consulta.pdf"}}] = shown.attachments

    {:ok, _} =
      Actions.run(UpdateCourseSettings, admin, %{
        "course_id" => course.id,
        "settings" => %{"student_attachments" => false}
      })

    assert {:error, :forbidden} = upload(student, course)
    assert {:ok, _} = upload(teacher, course)
  end

  test "no se adjunta un archivo ajeno ni uno de otro curso", %{admin: admin, course: course} do
    teacher = member(course, "teacher")
    {:ok, others} = upload(member(course, "teacher"), course)
    assert {:error, :invalid_attachment} = publish(teacher, course, [others])

    {:ok, other_course} = Actions.run(CreateCourse, admin, %{"name" => "Física"})
    {:ok, other_course} = Actions.run(PublishCourse, admin, %{"course_id" => other_course.id})

    {:ok, _} =
      Enrollments.enroll(institution(), other_course, teacher.user.id, %{
        role: "teacher",
        origin: "manual"
      })

    {:ok, elsewhere} = upload(teacher, other_course)
    assert {:error, :invalid_attachment} = publish(teacher, course, [elsewhere])
  end

  test "hasta #{10} archivos por publicación", %{course: course} do
    teacher = member(course, "teacher")

    files =
      for i <- 1..(Feed.max_attachments() + 1), do: elem(upload(teacher, course, "f#{i}.pdf"), 1)

    assert {:error, :too_many_attachments} = publish(teacher, course, files)
  end

  test "el borrador guarda los adjuntos y la publicación los conserva", %{course: course} do
    teacher = member(course, "teacher")
    {:ok, file} = upload(teacher, course)

    {:ok, _} =
      Actions.run(SaveDraft, teacher, %{
        "course_id" => course.id,
        "body" => body("Va con apunte"),
        "attachment_ids" => [file.id]
      })

    {:ok, post} =
      Actions.run(PublishPost, teacher, %{"course_id" => course.id, "body" => body("Listo")})

    assert attached(teacher, course, post) == ["apunte.pdf"]
  end

  test "quitar un adjunto al editar lo descarta del almacenamiento", %{course: course} do
    teacher = member(course, "teacher")
    {:ok, keep} = upload(teacher, course, "queda.pdf")
    {:ok, drop} = upload(teacher, course, "sale.pdf")
    {:ok, post} = publish(teacher, course, [keep, drop])

    {:ok, _} =
      Actions.run(UpdatePost, teacher, %{
        "post_id" => post.id,
        "body" => body("Corregido"),
        "attachment_ids" => [keep.id]
      })

    assert attached(teacher, course, post) == ["queda.pdf"]
    assert %{status: "rejected"} = Files.get(teacher, drop.id)
    assert {:error, :not_found} = Storage.head(drop.key)
  end

  test "borrar la publicación descarta sus adjuntos y los de sus respuestas", %{course: course} do
    teacher = member(course, "teacher")
    student = member(course, "student")
    {:ok, file} = upload(teacher, course)
    {:ok, post} = publish(teacher, course, [file])
    {:ok, in_reply} = upload(student, course, "respuesta.pdf")

    {:ok, _} =
      Actions.run(ReplyToPost, student, %{
        "post_id" => post.id,
        "body" => body("Va"),
        "attachment_ids" => [in_reply.id]
      })

    {:ok, _} = Actions.run(DeletePost, teacher, %{"post_id" => post.id})

    assert %{status: "rejected"} = Files.get(teacher, file.id)
    assert %{status: "rejected"} = Files.get(teacher, in_reply.id)
  end
end
