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

    # El editor arranca plegado: lo primero son las publicaciones.
    refute has_element?(view, "#feed-composer")
    view |> element("#feed-composer-open") |> render_click()

    view
    |> form("#feed-composer")
    |> render_submit(%{post: %{body: body("Bienvenidos a Programación I")}})

    assert has_element?(view, "#feed-posts article", "Bienvenidos a Programación I")
    refute has_element?(view, "#feed-composer [data-editor-input][value*=Bienvenidos]")
  end

  test "abrir y cerrar el editor sin escribir no deja borrador", %{conn: conn, course: course} do
    teacher = member(course, "teacher")
    conn = log_in_user(conn, teacher)
    {:ok, view, _html} = live(conn, Paths.course(institution(), course))

    view |> element("#feed-composer-open") |> render_click()
    view |> form("#feed-composer") |> render_change(%{post: %{body: ""}})
    view |> element(~s(#feed-composer [phx-click="close_composer"])) |> render_click()

    refute has_element?(view, "#feed-composer-open", "Continue your draft")

    {:ok, view, _html} = live(conn, Paths.course(institution(), course))
    refute has_element?(view, "#feed-composer-open", "Continue your draft")
  end

  test "el borrador se guarda al escribir y vuelve al recargar", %{conn: conn, course: course} do
    teacher = member(course, "teacher")
    conn = log_in_user(conn, teacher)
    {:ok, view, _html} = live(conn, Paths.course(institution(), course))

    view |> element("#feed-composer-open") |> render_click()
    view |> form("#feed-composer") |> render_change(%{post: %{body: body("A medio escribir")}})

    {:ok, view, _html} = live(conn, Paths.course(institution(), course))
    view |> element("#feed-composer-open", "Continue your draft") |> render_click()
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

    {:ok, view, _html} = open_post(conn, teacher, course, post)

    view
    |> element(~s(#feed-post-page [phx-click="edit"][phx-value-id="#{post.id}"]))
    |> render_click()

    view
    |> form("#edit-post-#{post.id}")
    |> render_submit(%{edit: %{body: body("Clase el martes")}})

    assert has_element?(view, "#feed-post-page article", "Clase el martes")
    assert has_element?(view, "#feed-post-page article", "edited")
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

  # La página de una publicación, con toda su conversación.
  defp open_post(conn, user, course, post),
    do: conn |> log_in_user(user) |> live(Paths.course_post(institution(), course, post))

  describe "tablón compacto y página de la publicación" do
    test "la tarjeta resume la conversación y lleva a la página", %{conn: conn, course: course} do
      teacher = member(course, "teacher")
      student = member(course, "student")
      post = publish(teacher, course, "Les dejo el enunciado del TP 3")

      {:ok, _} =
        Actions.run(
          Amauta.Feed.Actions.ReplyToPost,
          Amauta.Scope.for_user(institution(), student),
          %{"post_id" => post.id, "body" => body("¿Se entrega en grupo?")}
        )

      conn = log_in_user(conn, teacher)
      {:ok, view, _html} = live(conn, Paths.course(institution(), course))

      assert has_element?(view, "#post-open-#{post.id}", "Les dejo el enunciado del TP 3")
      assert has_element?(view, "#reply-summary-#{post.id}", "1 reply")
      # En el tablón no está la conversación ni el formulario para responder.
      refute has_element?(view, "#replies-#{post.id}")
      refute has_element?(view, "#reply-open-#{post.id}")

      assert {:ok, page, _html} =
               view
               |> element("#post-open-#{post.id}")
               |> render_click()
               |> follow_redirect(conn)

      assert has_element?(page, "#feed-post-page #replies-#{post.id}", "¿Se entrega en grupo?")
      refute has_element?(page, "#feed-composer")
    end

    test "si borran la publicación, su página vuelve al tablón", %{conn: conn, course: course} do
      teacher = member(course, "teacher")
      post = publish(teacher, course, "Aviso")
      {:ok, view, _html} = open_post(conn, teacher, course, post)

      view |> element(~s(#post-menu-#{post.id} [phx-click="delete"])) |> render_click()

      assert_redirect(view, Paths.course(institution(), course))
    end

    test "no se puede abrir una publicación de otra comisión", %{
      conn: conn,
      course: course,
      a: a
    } do
      teacher = member(course, "teacher")

      {:ok, post} =
        Actions.run(PublishPost, Amauta.Scope.for_user(institution(), teacher), %{
          "course_id" => course.id,
          "body" => body("Solo para la A"),
          "section_id" => a.id
        })

      outside = member(course, "student")

      assert_raise AmautaWeb.NotFoundError, fn ->
        open_post(conn, outside, course, post)
      end
    end
  end

  describe "respuestas" do
    test "un estudiante responde y la respuesta aparece en la publicación", %{
      conn: conn,
      course: course
    } do
      teacher = member(course, "teacher")
      student = member(course, "student")
      post = publish(teacher, course, "¿Dudas?")
      {:ok, view, _html} = open_post(conn, student, course, post)

      view |> element("#reply-open-#{post.id}") |> render_click()

      view
      |> form("#reply-form-#{post.id}")
      |> render_submit(%{reply: %{body: body("Sí, el punto 2")}})

      assert has_element?(view, "#replies-#{post.id} li", "Sí, el punto 2")
      assert has_element?(view, "#reply-summary-#{post.id}", "1 reply")
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

      {:ok, view, _html} = open_post(conn, teacher, course, post)

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
      {:ok, view, _html} = open_post(conn, teacher, course, post)

      view |> element(~s(#post-menu-#{post.id} [phx-click="toggle_replies"])) |> render_click()
      _ = render(view)

      assert has_element?(view, "#reply-summary-#{post.id}", "Replies are closed")
      refute has_element?(view, "#reply-open-#{post.id}")
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

      {:ok, teacher_view, _} = open_post(conn, teacher, course, post)
      {:ok, student_view, _} = open_post(build_conn(), student, course, post)

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

      {:ok, view, _} = open_post(conn, member(course, "student"), course, post)
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

      {:ok, view, _} = open_post(conn, teacher, course, post)

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

      # La fecha se elige desde el menú; antes no ocupa lugar en la tarjeta.
      refute has_element?(view, "#pin-expiry-#{post.id}")
      view |> element(~s(#pinned-#{post.id} [phx-click="edit_pin_expiry"])) |> render_click()

      view
      |> form("#pin-expiry-#{post.id}")
      |> render_change(%{pin: %{post_id: post.id, expires_on: date}})

      assert [%{pin_expires_at: %DateTime{}}] = Feed.list_pinned(scope, course)

      view |> element(~s(#pinned-#{post.id} [phx-click="close_pin_expiry"])) |> render_click()
      refute has_element?(view, "#pin-expiry-#{post.id}")
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

  describe "hilos y tableros largos" do
    test "muestra las últimas respuestas y trae las anteriores a pedido", %{
      conn: conn,
      course: course
    } do
      teacher = member(course, "teacher")
      scope = Amauta.Scope.for_user(institution(), teacher)
      post = publish(teacher, course, "Consultas")

      for i <- 1..40 do
        {:ok, _} =
          Actions.run(Amauta.Feed.Actions.ReplyToPost, scope, %{
            "post_id" => post.id,
            "body" => body("Respuesta #{i}")
          })
      end

      {:ok, view, _html} = open_post(conn, teacher, course, post)
      replies = "#replies-#{post.id} > ul > li"

      assert view |> element("#reply-summary-#{post.id}") |> render() =~ "40 replies"

      # En su página se ven más que en el tablón: las 3 de siempre y 30 más.
      assert count(view, replies) == 33

      assert has_element?(
               view,
               ~s(#replies-#{post.id} [phx-click="more_replies"]),
               "7 earlier replies"
             )

      view |> element(~s(#replies-#{post.id} [phx-click="more_replies"])) |> render_click()

      assert count(view, replies) == 40
      refute has_element?(view, ~s(#replies-#{post.id} [phx-click="more_replies"]))
    end

    test "la respuesta propia se suma sin desplazar otra", %{conn: conn, course: course} do
      teacher = member(course, "teacher")
      scope = Amauta.Scope.for_user(institution(), teacher)
      post = publish(teacher, course, "Consultas")

      for i <- 1..3 do
        {:ok, _} =
          Actions.run(Amauta.Feed.Actions.ReplyToPost, scope, %{
            "post_id" => post.id,
            "body" => body("Vieja #{i}")
          })
      end

      {:ok, view, _html} = open_post(conn, member(course, "student"), course, post)
      view |> element("#reply-open-#{post.id}") |> render_click()

      view
      |> form("#reply-form-#{post.id}")
      |> render_submit(%{reply: %{body: body("La mía")}})

      assert has_element?(view, "#replies-#{post.id}", "Vieja 1")
      assert has_element?(view, "#replies-#{post.id}", "La mía")
    end

    test "trae las publicaciones anteriores al llegar al final", %{conn: conn, course: course} do
      teacher = member(course, "teacher")
      for i <- 1..(Feed.page_size() + 2), do: publish(teacher, course, "Aviso #{i}")
      {:ok, view, _html} = open(conn, teacher, course)

      assert has_element?(view, ~s(#feed-posts[phx-viewport-bottom="more_posts"]))

      view |> element("#feed-more-posts") |> render_click()

      assert has_element?(view, "#post-open-" <> first_post_id(course, teacher))
      refute has_element?(view, "#feed-more-posts")
    end
  end

  defp count(view, selector),
    do: view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()

  defp first_post_id(course, user) do
    scope = Amauta.Scope.for_user(institution(), user)
    posts = Feed.list_posts(scope, course)
    [oldest | _] = Feed.list_posts(scope, course, %{}, before: List.last(posts)) |> Enum.reverse()
    oldest.id
  end

  @pdf "%PDF-1.7\n" <> :binary.copy("x", 200)

  # Sube un archivo como lo haría el navegador y avisa a la vista, como
  # hace `AmautaWeb.Components.DirectUpload` al terminar.
  defp attach(view, user, course, context, name \\ "programa.pdf") do
    scope = Amauta.Scope.for_user(institution(), user)

    {:ok, %{file: file}} =
      Actions.run(Amauta.Files.Actions.StartUpload, scope, %{
        "purpose" => "feed_attachment",
        "owner_id" => course.id,
        "filename" => name,
        "size" => byte_size(@pdf)
      })

    :ok = Amauta.Storage.put(file.key, @pdf)
    {:ok, file} = Actions.run(Amauta.Files.Actions.CompleteUpload, scope, %{"file_id" => file.id})

    send(
      view.pid,
      {AmautaWeb.Components.DirectUpload, "feed-upload-#{context}", {:uploaded, file}}
    )

    _ = render(view)
    file
  end

  describe "adjuntos" do
    test "se adjunta al escribir y queda en la publicación", %{conn: conn, course: course} do
      teacher = member(course, "teacher")
      {:ok, view, _html} = open(conn, teacher, course)

      view |> element("#feed-composer-open") |> render_click()
      attach(view, teacher, course, "composer")
      assert has_element?(view, "#feed-files-composer", "programa.pdf")

      view
      |> form("#feed-composer")
      |> render_submit(%{post: %{body: body("Programa de la materia")}})

      assert has_element?(view, "#feed-posts article", "programa.pdf")
      # El clip con la cantidad, junto a la fecha.
      assert has_element?(view, "#feed-posts [id^=post-files-count-]", "1 attachment")
      refute has_element?(view, "#feed-files-composer")
    end

    test "el adjunto del borrador vuelve al recargar y se puede quitar", %{
      conn: conn,
      course: course
    } do
      teacher = member(course, "teacher")
      conn = log_in_user(conn, teacher)
      {:ok, view, _html} = live(conn, Paths.course(institution(), course))
      view |> element("#feed-composer-open") |> render_click()
      file = attach(view, teacher, course, "composer")

      {:ok, view, _html} = live(conn, Paths.course(institution(), course))
      view |> element("#feed-composer-open", "Continue your draft") |> render_click()
      assert has_element?(view, "#feed-files-composer", "programa.pdf")

      view
      |> element(
        ~s(#feed-files-composer [phx-click="remove_file:composer"][phx-value-id="#{file.id}"])
      )
      |> render_click()

      refute has_element?(view, "#feed-files-composer")
      assert %{status: "rejected"} = Amauta.Files.get(institution(), file.id)
    end

    test "un estudiante adjunta al responder", %{conn: conn, course: course} do
      teacher = member(course, "teacher")
      student = member(course, "student")
      post = publish(teacher, course, "Consultas")
      {:ok, view, _html} = open_post(conn, student, course, post)

      view |> element("#reply-open-#{post.id}") |> render_click()
      attach(view, student, course, "reply", "duda.pdf")

      view
      |> form("#reply-form-#{post.id}")
      |> render_submit(%{reply: %{body: body("Adjunto mi duda")}})

      assert has_element?(view, "#replies-#{post.id} [id^=reply-files-]", "duda.pdf")
    end

    test "sin permiso para adjuntar no aparece el botón", %{conn: conn, course: course} do
      admin = member_scope("institution_admin")

      {:ok, _} =
        Actions.run(Amauta.Courses.Actions.UpdateCourseSettings, admin, %{
          "course_id" => course.id,
          "settings" => %{"student_attachments" => false}
        })

      teacher = member(course, "teacher")
      post = publish(teacher, course, "Consultas")
      {:ok, view, _html} = open_post(conn, member(course, "student"), course, post)

      view |> element("#reply-open-#{post.id}") |> render_click()
      assert has_element?(view, "#reply-form-#{post.id}")
      refute has_element?(view, "#feed-upload-reply")
    end
  end
end
