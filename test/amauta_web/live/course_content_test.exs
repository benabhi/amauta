defmodule AmautaWeb.CourseContentTest do
  @moduledoc "Pestaña Contenido y página de cada elemento: armar, ordenar, ocultar, materiales y permisos."
  use AmautaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Actions, Content, Enrollments, Scope, Storage}
  alias Amauta.Content.Actions.{CreateItem, CreateUnit}
  alias Amauta.Courses.Actions.{CreateCourse, PublishCourse}
  alias Amauta.Files.Actions.{CompleteUpload, StartUpload}
  alias AmautaWeb.Paths

  setup do
    admin = member_scope("institution_admin")
    {:ok, course} = Actions.run(CreateCourse, admin, %{"name" => "Programación I"})
    {:ok, course} = Actions.run(PublishCourse, admin, %{"course_id" => course.id})
    %{course: course, teacher: member(course, "teacher"), student: member(course, "student")}
  end

  defp member(course, role) do
    user = user_fixture()
    {:ok, _} = Enrollments.enroll(institution(), course, user.id, %{role: role, origin: "manual"})
    user
  end

  defp scope(user), do: Scope.for_user(institution(), user)

  defp unit(user, course, title, attrs \\ %{}) do
    {:ok, unit} =
      Actions.run(
        CreateUnit,
        scope(user),
        Map.merge(%{"course_id" => course.id, "title" => title}, attrs)
      )

    unit
  end

  defp page(user, unit, title, attrs \\ %{}) do
    {:ok, item} =
      Actions.run(
        CreateItem,
        scope(user),
        Map.merge(%{"unit_id" => unit.id, "kind" => "page", "title" => title}, attrs)
      )

    item
  end

  defp body(text),
    do:
      Jason.encode!(%{
        "type" => "doc",
        "content" => [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}
        ]
      })

  defp open(conn, user, course),
    do: conn |> log_in_user(user) |> live(Paths.course(institution(), course, :content))

  describe "índice" do
    test "el equipo docente crea una unidad desde la pestaña", %{
      conn: conn,
      course: course,
      teacher: t
    } do
      {:ok, view, _html} = open(conn, t, course)

      view |> element("#content-new-unit") |> render_click()

      view
      |> form("#unit-form-new", unit: %{title: "Introducción", visibility: "visible"})
      |> render_submit()

      assert has_element?(view, "#content-units", "Introducción")
      assert [%{title: "Introducción"}] = Content.list_units(scope(t), course)
    end

    test "programada pide la fecha, que se toma en la zona de la persona", %{
      conn: conn,
      course: course,
      teacher: t
    } do
      {:ok, view, _html} = open(conn, t, course)
      view |> element("#content-new-unit") |> render_click()

      view
      |> form("#unit-form-new", unit: %{title: "Más adelante", visibility: "scheduled"})
      |> render_change()

      assert has_element?(view, "#unit-form-new input[type=datetime-local]")

      view
      |> form("#unit-form-new",
        unit: %{title: "Más adelante", visibility: "scheduled", publish_local: "2099-03-01T08:00"}
      )
      |> render_submit()

      assert [%{visibility: "scheduled", publish_at: at}] = Content.list_units(scope(t), course)
      tz = t.timezone || institution().timezone

      assert DateTime.shift_zone!(at, tz)
             |> DateTime.to_naive()
             |> NaiveDateTime.truncate(:second) ==
               ~N[2099-03-01 08:00:00]
    end

    test "estudiantes ven lo publicado, sin controles", %{
      conn: conn,
      course: course,
      teacher: t,
      student: s
    } do
      u = unit(t, course, "Introducción")
      page(t, u, "Visible")
      page(t, u, "Borrador", %{"visibility" => "hidden"})
      unit(t, course, "Oculta", %{"visibility" => "hidden"})

      {:ok, view, _html} = open(conn, s, course)

      assert has_element?(view, "#content-units", "Visible")
      refute has_element?(view, "#content-units", "Borrador")
      refute has_element?(view, "#content-units", "Oculta")
      refute has_element?(view, "#content-new-unit")
      refute has_element?(view, "[data-drag-handle]")
      refute has_element?(view, ~s([phx-click="delete_unit"]))
    end

    test "ordena con el menú y arrastrando a otra unidad", %{
      conn: conn,
      course: course,
      teacher: t
    } do
      u1 = unit(t, course, "Uno")
      u2 = unit(t, course, "Dos")
      a = page(t, u1, "A")
      page(t, u1, "B")

      {:ok, view, _html} = open(conn, t, course)

      view
      |> element(~s(#unit-menu-#{u2.id} [phx-click="move_unit"][phx-value-dir="up"]))
      |> render_click()

      assert [%{title: "Dos"}, %{title: "Uno"}] = Content.list_units(scope(t), course)

      view
      |> element("#course-content")
      |> render_hook("drop", %{"type" => "item", "id" => a.id, "unit" => u2.id, "index" => 0})

      assert [%{items: [%{title: "A"}]}, %{items: [%{title: "B"}]}] =
               Content.list_units(scope(t), course)

      assert has_element?(view, "#unit-items-#{u2.id} #item-#{a.id}")
    end

    test "oculta y borra desde el menú", %{conn: conn, course: course, teacher: t} do
      u = unit(t, course, "Unidad")
      item = page(t, u, "Página")
      {:ok, view, _html} = open(conn, t, course)

      view
      |> element(~s(#item-menu-#{item.id} [phx-click="toggle_item"]))
      |> render_click()

      assert has_element?(view, "#item-#{item.id}", "Hidden")

      view |> element(~s(#unit-menu-#{u.id} [phx-click="delete_unit"])) |> render_click()
      refute has_element?(view, "#unit-#{u.id}")
    end
  end

  describe "página de un elemento" do
    test "crea una página y la muestra", %{conn: conn, course: course, teacher: t} do
      u = unit(t, course, "Unidad")
      conn = log_in_user(conn, t)
      {:ok, view, _html} = live(conn, Paths.new_course_item(institution(), course, u, "page"))

      {:ok, show, _html} =
        view
        |> form("#content-item-form",
          item: %{title: "¿Qué es un algoritmo?", visibility: "visible"}
        )
        |> render_submit(%{item: %{body: body("Una secuencia de pasos.")}})
        |> follow_redirect(conn)

      assert has_element?(show, "#content-item-body", "Una secuencia de pasos.")
      assert has_element?(show, "#content-item-edit")
    end

    @pdf "%PDF-1.7\n" <> :binary.copy("x", 200)

    test "un material lleva archivos subidos y un enlace", %{
      conn: conn,
      course: course,
      teacher: t
    } do
      u = unit(t, course, "Unidad")
      conn = log_in_user(conn, t)
      {:ok, view, _html} = live(conn, Paths.new_course_item(institution(), course, u, "material"))

      {:ok, %{file: file}} =
        Actions.run(StartUpload, scope(t), %{
          "purpose" => "content_material",
          "owner_id" => course.id,
          "filename" => "apunte.pdf",
          "size" => byte_size(@pdf)
        })

      :ok = Storage.put(file.key, @pdf)
      {:ok, file} = Actions.run(CompleteUpload, scope(t), %{"file_id" => file.id})
      send(view.pid, {AmautaWeb.Components.DirectUpload, "content-upload", {:uploaded, file}})
      assert has_element?(view, "#content-item-files", "apunte.pdf")

      {:ok, show, _html} =
        view
        |> form("#content-item-form",
          item: %{title: "Apunte", url: "https://www.example.com/apunte", visibility: "visible"}
        )
        |> render_submit()
        |> follow_redirect(conn)

      # El PDF se ve integrado en la página (RF-CON-008).
      assert has_element?(show, "#viewer-#{file.id} iframe")
      assert has_element?(show, "#viewer-#{file.id}", "apunte.pdf")
      assert has_element?(show, "#content-item-link", "example.com")
    end

    test "estudiantes no ven lo oculto ni editan", %{
      conn: conn,
      course: course,
      teacher: t,
      student: s
    } do
      u = unit(t, course, "Unidad")
      visible = page(t, u, "Visible")
      hidden = page(t, u, "Oculta", %{"visibility" => "hidden"})
      conn = log_in_user(conn, s)

      assert {:ok, view, _html} = live(conn, Paths.course_item(institution(), course, visible))
      refute has_element?(view, "#content-item-edit")

      assert_raise AmautaWeb.NotFoundError, fn ->
        live(conn, Paths.course_item(institution(), course, hidden))
      end

      assert_raise AmautaWeb.ForbiddenError, fn ->
        live(conn, Paths.edit_course_item(institution(), course, visible))
      end
    end
  end

  describe "recorrido" do
    test "quien cursa marca como hecho y avanza al siguiente", %{
      conn: conn,
      course: course,
      teacher: t,
      student: s
    } do
      u1 = unit(t, course, "Uno")
      a = page(t, u1, "A")
      b = page(t, unit(t, course, "Dos"), "B")
      conn = log_in_user(conn, s)

      {:ok, view, _html} = live(conn, Paths.course_item(institution(), course, a))

      assert has_element?(view, "#content-nav [aria-current=page]", "A")
      refute has_element?(view, "#content-item-prev")
      assert has_element?(view, "#content-item-next", "B")

      view |> element("#content-item-done") |> render_click()
      assert has_element?(view, "#content-item-done[aria-pressed=true]")
      assert MapSet.member?(Content.completed_ids(scope(s), course), a.id)

      {:ok, view, _html} =
        view |> element("#content-item-next") |> render_click() |> follow_redirect(conn)

      assert has_element?(view, "#content-item-prev", "A")
      assert has_element?(view, "#content-nav", "B")

      {:ok, index, _html} = live(conn, Paths.course(institution(), course, :content))
      assert has_element?(index, "#unit-#{u1.id}", "1 of 1 done")
      assert has_element?(index, "#item-#{a.id}", "Completed")
      refute has_element?(index, "#item-#{b.id}", "Completed")
    end

    test "el equipo docente no ve el botón de hecho", %{conn: conn, course: course, teacher: t} do
      a = page(t, unit(t, course, "Uno"), "A")

      {:ok, view, _html} =
        conn |> log_in_user(t) |> live(Paths.course_item(institution(), course, a))

      refute has_element?(view, "#content-item-done")
    end
  end

  describe "tarjeta en el tablón" do
    test "aparece en el tablón y lleva al elemento", %{
      conn: conn,
      course: course,
      teacher: t,
      student: s
    } do
      item = page(t, unit(t, course, "Unidad"), "Apunte de la unidad", %{"announce" => true})
      [card] = Amauta.Feed.list_posts(scope(s), course)
      conn = log_in_user(conn, s)

      {:ok, feed, _html} = live(conn, Paths.course(institution(), course))

      # Va en las novedades del curso, no en la conversación.
      assert has_element?(feed, "#feed-pinned #news-#{card.id}", "Apunte de la unidad")
      refute has_element?(feed, "#feed-posts", "Apunte de la unidad")
      refute has_element?(feed, "#news-#{card.id} [phx-click=toggle_replies]")

      {:ok, show, _html} =
        feed |> element("#post-open-#{card.id}") |> render_click() |> follow_redirect(conn)

      assert has_element?(show, "#content-item", "")
      assert page_title(show) =~ "Apunte de la unidad"

      # La página de la tarjeta, si se abre directo, lleva al elemento.
      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, Paths.course_post(institution(), course, card))

      assert to == Paths.course_item(institution(), course, item)
    end
  end
end
