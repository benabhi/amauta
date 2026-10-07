defmodule AmautaWeb.CourseFeedTest do
  @moduledoc "Pestaña Tablón: publicar, borrador, tiempo real, edición, respuestas, fijadas, moderación y permisos."
  use AmautaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Actions, Enrollments, Feed}
  alias Amauta.Courses.Actions.{CreateCourse, PublishCourse}
  alias Amauta.Enrollments.Actions.CreateSection
  alias Amauta.Feed.Actions.{PinPost, PublishPost}
  alias AmautaWeb.Paths

  setup do
    admin = member_scope("institution_admin")
    {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Programación I"})
    {:ok, course} = Actions.run(PublishCourse, admin, %{"course_id" => course.id})

    {:ok, a} =
      Actions.run(CreateSection, admin, %{"course_id" => course.id, "name" => "Comisión A"})

    %{course: course, a: a}
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

    user
  end

  test "el equipo docente publica desde el editor y aparece arriba", %{conn: conn, course: course} do
    teacher = member(course, "teacher")
    {:ok, view, _html} = conn |> log_in_user(teacher) |> live(Paths.course(institution(), course))

    view
    |> form("#feed-composer")
    |> render_submit(%{post: %{body: body("Bienvenidos a Programación I")}})

    assert has_element?(view, "#feed-posts article", "Bienvenidos a Programación I")
    refute has_element?(view, "#feed-composer [data-editor-input][value*=Bienvenidos]")
  end

  test "el borrador se guarda al escribir y vuelve al recargar", %{conn: conn, course: course} do
    teacher = member(course, "teacher")
    conn = log_in_user(conn, teacher)
    {:ok, view, _html} = live(conn, Paths.course(institution(), course))

    view |> form("#feed-composer") |> render_change(%{post: %{body: body("A medio escribir")}})

    {:ok, view, _html} = live(conn, Paths.course(institution(), course))
    assert has_element?(view, "#feed-composer [data-editor-input][value*=\"A medio escribir\"]")
  end

  test "lo nuevo llega en tiempo real a quien mira el tablón", %{conn: conn, course: course, a: a} do
    teacher = member(course, "teacher")
    in_a = member(course, "student", a)
    outside = member(course, "student")

    {:ok, view_a, _} = conn |> log_in_user(in_a) |> live(Paths.course(institution(), course))

    {:ok, view_out, _} =
      build_conn() |> log_in_user(outside) |> live(Paths.course(institution(), course))

    {:ok, post} =
      Actions.run(PublishPost, Amauta.Scope.for_user(institution(), teacher), %{
        "course_id" => course.id,
        "body" => body("Solo para la A"),
        "section_id" => a.id
      })

    # send_update llega en un mensaje aparte: el primer render lo deja pasar.
    _ = render(view_a)
    _ = render(view_out)
    assert render(view_a) =~ "Solo para la A"
    refute render(view_out) =~ "Solo para la A"

    {:ok, _} =
      Actions.run(
        Amauta.Feed.Actions.DeletePost,
        Amauta.Scope.for_user(institution(), teacher),
        %{"post_id" => post.id}
      )

    _ = render(view_a)
    refute render(view_a) =~ "Solo para la A"
  end

  test "un estudiante no ve el editor si no puede publicar", %{conn: conn, course: course} do
    student = member(course, "student")
    {:ok, view, _html} = conn |> log_in_user(student) |> live(Paths.course(institution(), course))
    refute has_element?(view, "#feed-composer")
    assert has_element?(view, "#course-feed", "Nothing posted yet")
  end

  test "edita la publicación propia y queda la marca", %{conn: conn, course: course} do
    teacher = member(course, "teacher")
    scope = Amauta.Scope.for_user(institution(), teacher)

    {:ok, post} =
      Actions.run(PublishPost, scope, %{
        "course_id" => course.id,
        "body" => body("Clase el lunes")
      })

    {:ok, view, _html} = conn |> log_in_user(teacher) |> live(Paths.course(institution(), course))

    view
    |> element(~s(#feed-posts [phx-click="edit"][phx-value-id="#{post.id}"]))
    |> render_click()

    view
    |> form("#edit-post-#{post.id}")
    |> render_submit(%{edit: %{body: body("Clase el martes")}})

    assert has_element?(view, "#feed-posts article", "Clase el martes")
    assert has_element?(view, "#feed-posts article", "edited")
    assert [%{edited_at: %DateTime{}}] = Feed.list_posts(scope, course)
  end

  defp publish(user, course, text) do
    {:ok, post} =
      Actions.run(PublishPost, Amauta.Scope.for_user(institution(), user), %{
        "course_id" => course.id,
        "body" => body(text)
      })

    post
  end

  defp open(conn, user, course),
    do: conn |> log_in_user(user) |> live(Paths.course(institution(), course))

  describe "respuestas" do
    test "un estudiante responde y la respuesta aparece en la publicación", %{
      conn: conn,
      course: course
    } do
      teacher = member(course, "teacher")
      student = member(course, "student")
      post = publish(teacher, course, "¿Dudas?")
      {:ok, view, _html} = open(conn, student, course)

      view |> element(~s(#replies-#{post.id} > button[phx-click="reply"])) |> render_click()

      view
      |> form("#reply-form-#{post.id}")
      |> render_submit(%{reply: %{body: body("Sí, el punto 2")}})

      assert has_element?(view, "#replies-#{post.id} li", "Sí, el punto 2")
      assert has_element?(view, "#replies-#{post.id}", "1 reply")
      refute has_element?(view, "#reply-form-#{post.id}")
    end

    test "responder a una respuesta la anida debajo", %{conn: conn, course: course} do
      teacher = member(course, "teacher")
      student = member(course, "student")
      post = publish(teacher, course, "Consultas")

      {:ok, top} =
        Actions.run(
          Amauta.Feed.Actions.ReplyToPost,
          Amauta.Scope.for_user(institution(), student),
          %{"post_id" => post.id, "body" => body("Primera")}
        )

      {:ok, view, _html} = open(conn, teacher, course)

      view
      |> element(~s(#reply-#{top.id} button[phx-click="reply"][phx-value-parent="#{top.id}"]))
      |> render_click()

      view
      |> form("#reply-form-#{post.id}")
      |> render_submit(%{reply: %{body: body("Respondida")}})

      assert has_element?(view, "#reply-#{top.id} ul li", "Respondida")
    end

    test "el autor cierra las respuestas y desaparece el botón", %{conn: conn, course: course} do
      teacher = member(course, "teacher")
      post = publish(teacher, course, "Aviso")
      {:ok, view, _html} = open(conn, teacher, course)

      view |> element(~s(#replies-#{post.id} [phx-click="toggle_replies"])) |> render_click()
      _ = render(view)

      assert has_element?(view, "#replies-#{post.id}", "Replies are closed")
      refute has_element?(view, ~s(#replies-#{post.id} > button[phx-click="reply"]))
    end
  end

  describe "moderación" do
    test "ocultar deja un aviso para el resto y el contenido para quien modera", %{
      conn: conn,
      course: course
    } do
      teacher = member(course, "teacher")
      student = member(course, "student")
      post = publish(teacher, course, "Consultas")

      {:ok, r} =
        Actions.run(
          Amauta.Feed.Actions.ReplyToPost,
          Amauta.Scope.for_user(institution(), member(course, "student")),
          %{"post_id" => post.id, "body" => body("Fuera de tema")}
        )

      {:ok, teacher_view, _} = open(conn, teacher, course)
      {:ok, student_view, _} = open(build_conn(), student, course)

      teacher_view
      |> element(~s(#reply-#{r.id} [phx-click="hide_reply"]))
      |> render_click()

      _ = render(teacher_view)
      _ = render(student_view)

      assert has_element?(teacher_view, "#reply-#{r.id}", "Fuera de tema")
      assert has_element?(teacher_view, "#reply-#{r.id}", "hidden")
      assert has_element?(student_view, "#reply-#{r.id}", "hidden by the teaching team")
      refute has_element?(student_view, "#reply-#{r.id}", "Fuera de tema")
    end

    test "un estudiante no ve los controles de moderación", %{conn: conn, course: course} do
      teacher = member(course, "teacher")
      post = publish(teacher, course, "Consultas")

      Actions.run(
        Amauta.Feed.Actions.ReplyToPost,
        Amauta.Scope.for_user(institution(), teacher),
        %{"post_id" => post.id, "body" => body("Hola")}
      )

      {:ok, view, _} = open(conn, member(course, "student"), course)
      refute has_element?(view, ~s([phx-click="hide_reply"]))
      refute has_element?(view, ~s([phx-click="mute"]))
      refute has_element?(view, ~s([phx-click="toggle_replies"]))
    end

    test "silenciar marca a la persona y avisa", %{conn: conn, course: course} do
      teacher = member(course, "teacher")
      student = member(course, "student")
      post = publish(teacher, course, "Consultas")

      {:ok, r} =
        Actions.run(
          Amauta.Feed.Actions.ReplyToPost,
          Amauta.Scope.for_user(institution(), student),
          %{"post_id" => post.id, "body" => body("Hola")}
        )

      {:ok, view, _} = open(conn, teacher, course)

      view
      |> element(~s(#reply-#{r.id} [phx-click="mute"][phx-value-muted="true"]))
      |> render_click()

      assert render(view) =~ "they can read, but not post or reply"
      assert has_element?(view, ~s(#reply-#{r.id} [phx-click="mute"][phx-value-muted="false"]))
      assert Feed.muted?(institution(), course, student.id)
    end
  end

  describe "fijadas" do
    test "quien modera fija con un clic y la publicación sube a destacadas", %{
      conn: conn,
      course: course
    } do
      teacher = member(course, "teacher")
      old = publish(teacher, course, "Programa de la materia")
      _new = publish(teacher, course, "Clase del lunes")
      {:ok, view, _html} = open(conn, teacher, course)

      view
      |> element(~s(#feed-posts [phx-click="pin"][phx-value-id="#{old.id}"]))
      |> render_click()

      _ = render(view)

      assert has_element?(view, "#pinned-#{old.id}", "Programa de la materia")
      assert has_element?(view, "#pinned-#{old.id}", "Pinned")
      refute has_element?(view, "#feed-posts #posts-#{old.id}")
      assert has_element?(view, "#course-pinned", "Programa de la materia")

      view |> element(~s(#pinned-#{old.id} [phx-click="unpin"])) |> render_click()
      _ = render(view)

      refute has_element?(view, "#pinned-#{old.id}")
      refute has_element?(view, "#course-pinned")
      assert has_element?(view, "#feed-posts #posts-#{old.id}")
    end

    test "se reordenan con los botones y con el arrastre", %{conn: conn, course: course} do
      teacher = member(course, "teacher")
      scope = Amauta.Scope.for_user(institution(), teacher)
      one = publish(teacher, course, "Uno")
      two = publish(teacher, course, "Dos")
      three = publish(teacher, course, "Tres")

      for post <- [one, two],
          do: {:ok, _} = Actions.run(PinPost, scope, %{"post_id" => post.id, "pinned" => true})

      {:ok, view, _html} = open(conn, teacher, course)

      view
      |> element(~s(#pinned-#{two.id} [phx-click="move_pin"][phx-value-dir="up"]))
      |> render_click()

      assert Enum.map(Feed.list_pinned(scope, course), & &1.id) == [two.id, one.id]

      # Arrastrar desde el listado a la zona de destacadas, entre las dos.
      view
      |> element("#feed-pinned")
      |> render_hook("pin", %{"id" => three.id, "ids" => [two.id, three.id, one.id]})

      assert Enum.map(Feed.list_pinned(scope, course), & &1.id) == [two.id, three.id, one.id]
    end

    test "el vencimiento se elige con una fecha", %{conn: conn, course: course} do
      teacher = member(course, "teacher")
      scope = Amauta.Scope.for_user(institution(), teacher)
      post = publish(teacher, course, "Inscripción")
      {:ok, _} = Actions.run(PinPost, scope, %{"post_id" => post.id, "pinned" => true})
      {:ok, view, _html} = open(conn, teacher, course)

      date = Date.utc_today() |> Date.add(7) |> Date.to_iso8601()

      view
      |> form("#pin-expiry-#{post.id}")
      |> render_change(%{pin: %{post_id: post.id, expires_on: date}})

      assert [%{pin_expires_at: %DateTime{}}] = Feed.list_pinned(scope, course)
    end

    test "un estudiante ve las fijadas pero no los controles", %{conn: conn, course: course} do
      teacher = member(course, "teacher")
      post = publish(teacher, course, "Programa")

      {:ok, _} =
        Actions.run(PinPost, Amauta.Scope.for_user(institution(), teacher), %{
          "post_id" => post.id,
          "pinned" => true
        })

      {:ok, view, _html} = open(conn, member(course, "student"), course)
      assert has_element?(view, "#pinned-#{post.id}", "Programa")
      refute has_element?(view, ~s([phx-click="unpin"]))
      refute has_element?(view, ~s([phx-click="move_pin"]))
      refute has_element?(view, "[data-drag-handle]")
    end
  end
end
