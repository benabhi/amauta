defmodule AmautaWeb.E2E.CourseFeedTest do
  @moduledoc "Tablón en un navegador real: escribir con el editor de bloques, mencionar y publicar."
  use AmautaWeb.E2ECase

  alias Amauta.{Actions, Enrollments}
  alias Amauta.Courses.Actions.{CreateCourse, PublishCourse}
  alias AmautaWeb.Paths

  setup do
    admin = member_scope("institution_admin")
    {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Programación I"})
    {:ok, course} = Actions.run(PublishCourse, admin, %{"course_id" => course.id})
    teacher = user_fixture()

    {:ok, _} =
      Enrollments.enroll(institution(), course, teacher.id, %{role: "teacher", origin: "manual"})

    %{teacher: teacher, course: course}
  end

  @editor "#feed-composer [data-editor-content] .ProseMirror"

  # El editor arranca plegado en una línea: se abre al tocarla.
  defp open_composer(session), do: session |> click("#feed-composer-open") |> assert_has(@editor)

  test "publica un aviso con formato y el editor queda vacío", %{
    conn: conn,
    teacher: teacher,
    course: course
  } do
    conn
    |> log_in(teacher, Paths.course(institution(), course))
    |> open_composer()
    |> click(@editor)
    |> type(@editor, "Mañana no hay clase ")
    |> press(@editor, "Control+b")
    |> type(@editor, "por paro")
    |> click_button("Publish")
    # En el tablón, la tarjeta compacta; el editor vuelve a plegarse.
    |> assert_has("#feed-posts article", text: "Mañana no hay clase por paro")
    |> assert_has("#feed-composer-open")
    # El formato se ve en la página de la publicación.
    |> click("#feed-posts article a[data-open]")
    |> assert_has("#feed-post-page article strong", text: "por paro")
  end

  test "menciona con «@» a alguien del curso", %{conn: conn, teacher: teacher, course: course} do
    student = user_fixture(%{first_name: "Grace", last_name: "Hopper"})

    {:ok, _} =
      Enrollments.enroll(institution(), course, student.id, %{role: "student", origin: "manual"})

    conn
    |> log_in(teacher, Paths.course(institution(), course))
    |> open_composer()
    |> click(@editor)
    |> type(@editor, "Felicitaciones @gra")
    |> assert_has(".rich-slash-item", text: "Grace Hopper")
    |> press(@editor, "Enter")
    |> click_button("Publish")
    |> click("#feed-posts article a[data-open]")
    |> assert_has("#feed-post-page article .rich-mention", text: "@Grace Hopper")
  end

  @video_input "#feed-composer .rich-video-edit input"
  @video "#feed-post-page article .rich-video iframe[src$='/embed/dQw4w9WgXcQ']"

  defp insert_video_block(session) do
    session
    |> click(@editor)
    |> type(@editor, "Mirar este video:")
    |> press(@editor, "Enter")
    |> type(@editor, "/video")
    |> assert_has(".rich-slash-item", text: "Video")
    |> press(@editor, "Enter")
    |> assert_has(@video_input)
  end

  test "un video con el enlace escrito se publica aunque no se apriete Enter", %{
    conn: conn,
    teacher: teacher,
    course: course
  } do
    conn
    |> log_in(teacher, Paths.course(institution(), course))
    |> open_composer()
    |> insert_video_block()
    |> type(@video_input, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    |> click_button("Publish")
    |> click("#feed-posts article a[data-open]")
    |> assert_has(@video)
  end

  test "un video se toma apenas se pega el enlace", %{
    conn: conn,
    teacher: teacher,
    course: course
  } do
    paste = """
    const input = document.querySelector("#{@video_input}")
    input.value = "https://youtu.be/dQw4w9WgXcQ"
    input.dispatchEvent(new InputEvent("input", {inputType: "insertFromPaste", bubbles: true}))
    """

    conn
    |> log_in(teacher, Paths.course(institution(), course))
    |> open_composer()
    |> insert_video_block()
    |> evaluate(paste)
    |> assert_has("#feed-composer .rich-video-edit .rich-video iframe")
    |> refute_has(@video_input)
    |> click_button("Publish")
    |> click("#feed-posts article a[data-open]")
    |> assert_has(@video)
  end

  test "en su página, una publicación larga se recorta y se despliega con «Ver más»", %{
    conn: conn,
    teacher: teacher,
    course: course
  } do
    paragraphs =
      for i <- 1..14,
          do: %{
            "type" => "paragraph",
            "content" => [
              %{"type" => "text", "text" => "Párrafo #{i} del programa de la materia."}
            ]
          }

    {:ok, post} =
      Actions.run(
        Amauta.Feed.Actions.PublishPost,
        Amauta.Scope.for_user(institution(), teacher),
        %{
          "course_id" => course.id,
          "body" => Jason.encode!(%{"type" => "doc", "content" => paragraphs})
        }
      )

    toggle = "#post-text-#{post.id} [data-collapse-toggle]"

    conn
    |> log_in(teacher, Paths.course_post(institution(), course, post))
    |> assert_has(toggle, text: "Show more")
    |> click(toggle)
    |> assert_has("#post-text-#{post.id}[data-expanded]")
    |> assert_has(toggle, text: "Show less")
  end

  test "avisa las publicaciones nuevas a quien lee más abajo", %{
    conn: conn,
    teacher: teacher,
    course: course
  } do
    other = user_fixture()

    {:ok, _} =
      Enrollments.enroll(institution(), course, other.id, %{role: "teacher", origin: "manual"})

    publish = fn text ->
      Actions.run(Amauta.Feed.Actions.PublishPost, Amauta.Scope.for_user(institution(), other), %{
        "course_id" => course.id,
        "body" =>
          Jason.encode!(%{
            "type" => "doc",
            "content" => [
              %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}
            ]
          })
      })
    end

    for i <- 1..8, do: {:ok, _} = publish.("Aviso #{i}")

    conn
    |> log_in(teacher, Paths.course(institution(), course))
    |> assert_has("#feed-posts article", text: "Aviso 1")
    |> evaluate("window.scrollTo(0, document.body.scrollHeight)")
    |> tap(fn _ -> {:ok, _} = publish.("Aviso nuevo") end)
    |> assert_has("[data-new-posts]", text: "1 new post")
    |> evaluate(
      "getComputedStyle(document.querySelector('[data-new-posts]')).display",
      &assert(&1 == "flex")
    )
  end
end
