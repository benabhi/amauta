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
end
