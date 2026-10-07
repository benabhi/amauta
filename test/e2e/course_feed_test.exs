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

  test "publica un aviso con formato y el editor queda vacío", %{
    conn: conn,
    teacher: teacher,
    course: course
  } do
    conn
    |> log_in(teacher, Paths.course(institution(), course))
    |> assert_has(@editor)
    |> click(@editor)
    |> type(@editor, "Mañana no hay clase ")
    |> press(@editor, "Control+b")
    |> type(@editor, "por paro")
    |> click_button("Publish")
    |> assert_has("#feed-posts article strong", text: "por paro")
    |> assert_has("#feed-posts article", text: "Mañana no hay clase")
    |> refute_has("#feed-composer .ProseMirror", text: "Mañana")
  end

  test "menciona con «@» a alguien del curso", %{conn: conn, teacher: teacher, course: course} do
    student = user_fixture(%{first_name: "Grace", last_name: "Hopper"})

    {:ok, _} =
      Enrollments.enroll(institution(), course, student.id, %{role: "student", origin: "manual"})

    conn
    |> log_in(teacher, Paths.course(institution(), course))
    |> assert_has(@editor)
    |> click(@editor)
    |> type(@editor, "Felicitaciones @gra")
    |> assert_has(".rich-slash-item", text: "Grace Hopper")
    |> press(@editor, "Enter")
    |> click_button("Publish")
    |> assert_has("#feed-posts article .rich-mention", text: "@Grace Hopper")
  end

  test "una publicación larga se recorta y se despliega con «Ver más»", %{
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
    |> log_in(teacher, Paths.course(institution(), course))
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
