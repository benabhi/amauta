defmodule Amauta.NotificationsTest do
  @moduledoc "Notificaciones: audiencias, motivos, menciones, agrupación, preferencias y email agrupado (C12, RF-EML-004 y 009)."
  use Amauta.DataCase, async: true
  use Oban.Testing, repo: Amauta.Repo, prefix: "global"

  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Actions, Enrollments, Notifications, Scope}
  alias Amauta.Courses.Actions.{CreateCourse, PublishCourse}
  alias Amauta.Enrollments.Actions.CreateSection
  alias Amauta.Feed.Actions.{PublishPost, ReplyToPost}
  alias Amauta.Notifications.{DeliverWorker, EmailDigestWorker, Message}

  setup do
    admin = member_scope("institution_admin")
    {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Programación I"})
    {:ok, course} = Actions.run(PublishCourse, admin, %{"course_id" => course.id})
    {:ok, a} = Actions.run(CreateSection, admin, %{"course_id" => course.id, "name" => "A"})
    %{course: course, a: a, teacher: member(course, "teacher")}
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

  defp doc(nodes),
    do:
      Jason.encode!(%{
        "type" => "doc",
        "content" => [%{"type" => "paragraph", "content" => nodes}]
      })

  defp text(t), do: %{"type" => "text", "text" => t}

  defp mention(scope),
    do: %{"type" => "mention", "attrs" => %{"id" => scope.user.id, "label" => "x"}}

  # Corre los trabajos de entrega encolados (como haría Oban).
  defp drain do
    for job <- all_enqueued(worker: DeliverWorker) do
      :ok = perform_job(DeliverWorker, job.args)
    end
  end

  defp events(scope), do: Notifications.list(scope).entries |> Enum.map(& &1.event)

  describe "publicaciones" do
    test "llegan al curso, con su motivo, y no a quien publica", %{course: course, teacher: t} do
      student = member(course, "student")

      {:ok, _} =
        Actions.run(PublishPost, t, %{"course_id" => course.id, "body" => doc([text("Hola")])})

      drain()

      assert ["feed.post_published"] = events(student)
      assert [] = events(t)
      assert Notifications.unread_count(student) == 1

      [n] = Notifications.list(student).entries
      assert n.reason == "role:student"
      assert Message.reason(n) =~ "Programación I"
      assert Message.text(n) =~ "Programación I"
    end

    test "lo dirigido a una comisión no llega al resto", %{course: course, a: a, teacher: t} do
      in_a = member(course, "student", a)
      other = member(course, "student")

      {:ok, _} =
        Actions.run(PublishPost, t, %{
          "course_id" => course.id,
          "section_id" => a.id,
          "body" => doc([text("Solo A")])
        })

      drain()
      assert [_] = events(in_a)
      assert [] = events(other)
    end

    test "a quien mencionan le llega la mención, no las dos", %{course: course, teacher: t} do
      student = member(course, "student")

      {:ok, _} =
        Actions.run(PublishPost, t, %{
          "course_id" => course.id,
          "body" => doc([text("Atención "), mention(student)])
        })

      drain()
      assert ["feed.mentioned"] = events(student)
    end

    test "las respuestas a una publicación se agrupan", %{course: course, teacher: t} do
      s1 = member(course, "student")
      s2 = member(course, "student")

      {:ok, post} =
        Actions.run(PublishPost, t, %{"course_id" => course.id, "body" => doc([text("¿Dudas?")])})

      drain()

      for s <- [s1, s2],
          do:
            {:ok, _} =
              Actions.run(ReplyToPost, s, %{"post_id" => post.id, "body" => doc([text("Sí")])})

      drain()

      assert [%{event: "feed.reply_created", count: 2} = n] = Notifications.list(t).entries
      assert Message.text(n) =~ "2"
      # s1 participó: le llega la respuesta de s2.
      assert "feed.reply_created" in events(s1)
    end
  end

  describe "preferencias" do
    test "sin el canal de la plataforma no queda sin leer; sin canales, nada", %{
      course: course,
      teacher: t
    } do
      student = member(course, "student")
      {:ok, _} = Notifications.set_preference(student, "feed.post_published", "platform", false)

      {:ok, _} =
        Actions.run(PublishPost, t, %{"course_id" => course.id, "body" => doc([text("1")])})

      drain()
      assert Notifications.unread_count(student) == 0

      {:ok, _} = Notifications.set_preference(student, "feed.post_published", "email", false)

      {:ok, _} =
        Actions.run(PublishPost, t, %{"course_id" => course.id, "body" => doc([text("2")])})

      drain()
      assert [_] = Notifications.list(student).entries

      assert %{{"feed.post_published", "email"} => false} = Notifications.preferences(student)
    end
  end

  describe "lectura" do
    test "marcar una y todas como leídas", %{course: course, teacher: t} do
      student = member(course, "student")

      for i <- 1..2,
          do:
            {:ok, _} =
              Actions.run(PublishPost, t, %{
                "course_id" => course.id,
                "body" => doc([text("#{i}")])
              })

      drain()
      [n | _] = Notifications.list(student).entries
      {:ok, _} = Notifications.mark_read(student, n.id)
      assert Notifications.unread_count(student) == 1

      assert {:error, :not_found} = Notifications.mark_read(t, n.id)

      {:ok, 1} = Notifications.mark_all_read(student)
      assert Notifications.unread_count(student) == 0
    end
  end

  describe "otros eventos" do
    test "matricular avisa a la persona", %{course: course} do
      admin = member_scope("institution_admin")
      user = user_fixture()

      {:ok, _} =
        Actions.run(Amauta.Enrollments.Actions.EnrollUser, admin, %{
          "course_id" => course.id,
          "user_id" => user.id,
          "role" => "student"
        })

      drain()
      assert ["enrollment.created"] = events(Scope.for_user(institution(), user))
    end

    test "el contenido que se publica y avisa notifica", %{course: course, teacher: t} do
      student = member(course, "student")

      {:ok, unit} =
        Actions.run(Amauta.Content.Actions.CreateUnit, t, %{
          "course_id" => course.id,
          "title" => "U"
        })

      {:ok, _} =
        Actions.run(Amauta.Content.Actions.CreateItem, t, %{
          "unit_id" => unit.id,
          "kind" => "material",
          "title" => "Apunte",
          "announce" => true
        })

      drain()
      assert ["content.item_published"] = events(student)
    end
  end

  describe "email agrupado" do
    test "junta lo pendiente en un email con baja en un clic", %{course: course, teacher: t} do
      student = member(course, "student")

      for i <- 1..2,
          do:
            {:ok, _} =
              Actions.run(PublishPost, t, %{
                "course_id" => course.id,
                "body" => doc([text("Aviso #{i}")])
              })

      drain()

      # Un solo trabajo agendado para la persona, aunque llegaron dos.
      assert [job] =
               all_enqueued(worker: EmailDigestWorker, args: %{"user_id" => student.user.id})

      assert :ok = perform_job(EmailDigestWorker, job.args)

      address = student.user.email
      # (el de confirmación de la cuenta también le llegó: se busca el de avisos)
      assert_received {:email,
                       %{to: [{_, ^address}], headers: %{"List-Unsubscribe-Post" => one_click}} =
                         email}

      assert one_click == "List-Unsubscribe=One-Click"
      assert email.headers["List-Unsubscribe"] =~ "/unsubscribe/"
      assert email.text_body =~ "Aviso 1"
      assert email.text_body =~ "Aviso 2"
      assert email.html_body =~ institution().name

      assert Enum.all?(Notifications.list(student).entries, &(not &1.email_pending))
    end
  end
end
