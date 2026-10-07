defmodule Amauta.FeedTest do
  @moduledoc "Tablón: publicar, borradores, destinatarios, respuestas, fijadas, moderación, visibilidad y permisos (RF-TAB-001 a 004 y 006 a 008)."
  use Amauta.DataCase, async: true

  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Actions, Audit, Enrollments, Feed, Scope}
  alias Amauta.Courses.Actions.{CreateCourse, PublishCourse, UpdateCourseSettings}
  alias Amauta.Enrollments.Actions.CreateSection

  alias Amauta.Feed.Actions.{
    DeletePost,
    DeleteReply,
    HideReply,
    MuteMember,
    PinPost,
    PublishPost,
    ReorderPinned,
    ReplyToPost,
    SaveDraft,
    SetRepliesEnabled,
    UpdatePost,
    UpdateReply
  }

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

  defp reply(scope, post, text, parent \\ nil) do
    Actions.run(ReplyToPost, scope, %{
      "post_id" => post.id,
      "parent_id" => parent && parent.id,
      "body" => body(text)
    })
  end

  defp reply_texts(scope, course, post) do
    scope
    |> Feed.get_visible(course, post.id)
    |> Map.fetch!(:replies)
    |> Enum.map(&Amauta.RichText.to_text(&1.body))
  end

  describe "respuestas" do
    test "un estudiante responde, se audita y se avisa en tiempo real", %{course: course} do
      teacher = member(course, "teacher")
      student = member(course, "student")
      {:ok, post} = publish(teacher, course, "¿Dudas del TP?")
      Phoenix.PubSub.subscribe(Amauta.PubSub, Feed.topic(course))

      assert {:ok, r} = reply(student, post, "Sí, el punto 2")
      assert r.author_id == student.user.id
      assert_received {:feed, :updated, %{id: id}}
      assert id == post.id
      assert reply_texts(teacher, course, post) == ["Sí, el punto 2"]
      assert "feed.reply.create" in Enum.map(Audit.list_events(student), & &1.action)
    end

    test "un solo nivel de anidación", %{course: course} do
      teacher = member(course, "teacher")
      student = member(course, "student")
      {:ok, post} = publish(teacher, course, "Consultas")
      {:ok, top} = reply(student, post, "Primera")
      {:ok, child} = reply(teacher, post, "Respuesta", top)
      {:ok, grandchild} = reply(student, post, "Otra", child)

      assert child.parent_id == top.id
      assert grandchild.parent_id == top.id
    end

    test "la respuesta padre tiene que ser de la misma publicación", %{course: course} do
      teacher = member(course, "teacher")
      {:ok, one} = publish(teacher, course, "Uno")
      {:ok, two} = publish(teacher, course, "Dos")
      {:ok, r} = reply(teacher, one, "En uno")

      assert {:error, :not_found} = reply(teacher, two, "Cruzada", r)
    end

    test "no se responde vacío", %{course: course} do
      teacher = member(course, "teacher")
      {:ok, post} = publish(teacher, course, "Hola")

      assert {:error, changeset} =
               Actions.run(ReplyToPost, teacher, %{"post_id" => post.id, "body" => ""})

      assert %{body: ["write something first"]} = errors_on(changeset)
    end

    test "no se responde a lo que no se ve", %{course: course, a: a, b: b} do
      teacher = member(course, "teacher")
      {:ok, for_b} = publish(teacher, course, "Para B", b)
      assert {:error, :not_found} = reply(member(course, "student", a), for_b, "Hola")
    end

    test "con los comentarios del curso desactivados no se responde", ctx do
      %{admin: admin, course: course} = ctx
      teacher = member(course, "teacher")
      {:ok, post} = publish(teacher, course, "Hola")

      {:ok, _} =
        Actions.run(UpdateCourseSettings, admin, %{
          "course_id" => course.id,
          "settings" => %{"comments_enabled" => false}
        })

      course = Amauta.Courses.get(admin, course.id)
      refute Feed.can_reply?(teacher, course)
      assert {:error, :forbidden} = reply(member(course, "student"), post, "Hola")
    end

    test "el autor o quien modera cierra las respuestas", %{course: course} do
      teacher = member(course, "teacher")
      student = member(course, "student")
      {:ok, post} = publish(teacher, course, "Aviso")

      params = %{"post_id" => post.id, "enabled" => false}
      assert {:error, :forbidden} = Actions.run(SetRepliesEnabled, student, params)
      assert {:ok, %{replies_enabled: false}} = Actions.run(SetRepliesEnabled, teacher, params)
      assert {:error, :forbidden} = reply(student, post, "Hola")

      lead = member(course, "course_lead")

      assert {:ok, %{replies_enabled: true}} =
               Actions.run(SetRepliesEnabled, lead, %{params | "enabled" => true})

      assert {:ok, _} = reply(student, post, "Hola")
    end

    test "editar la propia deja la marca; la ajena, no", %{course: course} do
      teacher = member(course, "teacher")
      student = member(course, "student")
      {:ok, post} = publish(teacher, course, "Consultas")
      {:ok, r} = reply(student, post, "Primera")

      params = %{"reply_id" => r.id, "body" => body("Corregida")}
      assert {:error, :forbidden} = Actions.run(UpdateReply, teacher, params)
      assert {:ok, %{edited_at: %DateTime{}}} = Actions.run(UpdateReply, student, params)
      assert reply_texts(teacher, course, post) == ["Corregida"]
    end

    test "elimina su autor o quien modera; al borrar la de primer nivel caen las anidadas", ctx do
      %{course: course} = ctx
      teacher = member(course, "teacher")
      student = member(course, "student")
      other = member(course, "student")
      {:ok, post} = publish(teacher, course, "Consultas")
      {:ok, top} = reply(student, post, "Primera")
      {:ok, _} = reply(other, post, "Anidada", top)
      {:ok, own} = reply(other, post, "Propia")

      assert {:error, :forbidden} = Actions.run(DeleteReply, other, %{"reply_id" => top.id})
      assert {:ok, _} = Actions.run(DeleteReply, other, %{"reply_id" => own.id})
      assert {:ok, _} = Actions.run(DeleteReply, teacher, %{"reply_id" => top.id})
      assert reply_texts(teacher, course, post) == []
    end
  end

  describe "moderación" do
    test "quien modera oculta y vuelve a mostrar una respuesta", %{course: course} do
      teacher = member(course, "teacher")
      student = member(course, "student")
      {:ok, post} = publish(teacher, course, "Consultas")
      {:ok, r} = reply(student, post, "Fuera de tema")

      params = %{"reply_id" => r.id, "hidden" => true}
      assert {:error, :forbidden} = Actions.run(HideReply, student, params)
      assert {:ok, %{hidden_at: %DateTime{}}} = Actions.run(HideReply, teacher, params)

      # Ocultar no borra: sigue en la base, con su contenido.
      assert reply_texts(teacher, course, post) == ["Fuera de tema"]

      assert {:ok, %{hidden_at: nil}} =
               Actions.run(HideReply, teacher, %{params | "hidden" => false})
    end

    test "silenciar impide publicar y responder, pero no leer", ctx do
      %{admin: admin, course: course} = ctx

      {:ok, _} =
        Actions.run(UpdateCourseSettings, admin, %{
          "course_id" => course.id,
          "settings" => %{"feed_posting" => "everyone"}
        })

      course = Amauta.Courses.get(admin, course.id)
      teacher = member(course, "teacher")
      student = member(course, "student")
      {:ok, post} = publish(teacher, course, "Consultas")

      params = %{"course_id" => course.id, "user_id" => student.user.id, "muted" => true}
      assert {:error, :forbidden} = Actions.run(MuteMember, member(course, "student"), params)
      assert {:ok, _} = Actions.run(MuteMember, teacher, params)
      # Silenciar dos veces no falla.
      assert {:ok, _} = Actions.run(MuteMember, teacher, params)

      assert Feed.muted?(student, course)
      assert {:error, :forbidden} = reply(student, post, "Hola")
      assert {:error, :forbidden} = publish(student, course, "Hola")
      assert texts(student, course) == ["Consultas"]

      assert {:ok, _} = Actions.run(MuteMember, teacher, %{params | "muted" => false})
      assert {:ok, _} = reply(student, post, "Hola")
    end

    test "no se silencia a quien modera ni a uno mismo", %{course: course} do
      teacher = member(course, "teacher")
      lead = member(course, "course_lead")
      mute = &%{"course_id" => course.id, "user_id" => &1.user.id, "muted" => true}

      assert {:error, :forbidden} = Actions.run(MuteMember, teacher, mute.(lead))
      assert {:error, :forbidden} = Actions.run(MuteMember, teacher, mute.(teacher))
    end
  end

  defp pin(scope, post, attrs \\ %{}) do
    Actions.run(PinPost, scope, Map.merge(%{"post_id" => post.id, "pinned" => true}, attrs))
  end

  defp pinned_texts(scope, course) do
    scope |> Feed.list_pinned(course) |> Enum.map(&Amauta.RichText.to_text(&1.body))
  end

  describe "fijadas" do
    test "quien modera fija; van arriba en orden y salen del listado común", %{course: course} do
      teacher = member(course, "teacher")
      {:ok, one} = publish(teacher, course, "Uno")
      {:ok, two} = publish(teacher, course, "Dos")
      {:ok, _} = publish(teacher, course, "Tres")
      Phoenix.PubSub.subscribe(Amauta.PubSub, Feed.topic(course))

      assert {:error, :forbidden} = pin(member(course, "student"), one)
      assert {:ok, %{pin_position: 1}} = pin(teacher, two)
      assert {:ok, %{pin_position: 2}} = pin(teacher, one)
      assert_received {:feed, :pinned, _}

      assert pinned_texts(teacher, course) == ["Dos", "Uno"]
      assert texts(teacher, course) == ["Tres"]
      assert "feed.post.pin" in Enum.map(Audit.list_events(teacher), & &1.action)
    end

    test "desfijar la devuelve al listado común", %{course: course} do
      teacher = member(course, "teacher")
      {:ok, post} = publish(teacher, course, "Uno")
      {:ok, _} = pin(teacher, post)
      {:ok, _} = pin(teacher, post, %{"pinned" => false})

      assert pinned_texts(teacher, course) == []
      assert texts(teacher, course) == ["Uno"]
    end

    test "se ordenan a mano, sin mover las que la persona no ve", ctx do
      %{course: course, a: a, b: b} = ctx
      lead = member(course, "course_lead")
      {:ok, all} = publish(lead, course, "Todos")
      {:ok, for_a} = publish(lead, course, "Para A", a)
      {:ok, for_b} = publish(lead, course, "Para B", b)
      for post <- [all, for_a, for_b], do: {:ok, _} = pin(lead, post)

      params = %{"course_id" => course.id, "post_ids" => [for_b.id, all.id]}
      assert {:error, :forbidden} = Actions.run(ReorderPinned, member(course, "student"), params)
      assert {:ok, _} = Actions.run(ReorderPinned, lead, params)

      # Las que faltan en la lista quedan al final, en su orden.
      assert pinned_texts(lead, course) == ["Para B", "Todos", "Para A"]
      assert pinned_texts(member(course, "student", a), course) == ["Todos", "Para A"]
    end

    test "vencida, deja de estar fijada sola", %{course: course} do
      teacher = member(course, "teacher")
      {:ok, post} = publish(teacher, course, "Inscripción abierta")
      tomorrow = DateTime.add(DateTime.utc_now(), 1, :day)
      {:ok, pinned} = pin(teacher, post, %{"expires_at" => tomorrow})
      assert pinned_texts(teacher, course) == ["Inscripción abierta"]

      pinned
      |> Ecto.Changeset.change(pin_expires_at: DateTime.add(DateTime.utc_now(), -1, :minute))
      |> Amauta.Repo.update!(Amauta.Tenancy.opts(teacher))

      assert pinned_texts(teacher, course) == []
      assert texts(teacher, course) == ["Inscripción abierta"]
    end

    test "cambiar el vencimiento no la mueve; tiene que ser a futuro", %{course: course} do
      teacher = member(course, "teacher")
      {:ok, one} = publish(teacher, course, "Uno")
      {:ok, two} = publish(teacher, course, "Dos")
      {:ok, _} = pin(teacher, one)
      {:ok, _} = pin(teacher, two)

      next_week = DateTime.add(DateTime.utc_now(), 7, :day)
      assert {:ok, %{pin_position: 1}} = pin(teacher, one, %{"expires_at" => next_week})

      yesterday = DateTime.add(DateTime.utc_now(), -1, :day)
      assert {:error, changeset} = pin(teacher, one, %{"expires_at" => yesterday})
      assert %{expires_at: ["must be in the future"]} = errors_on(changeset)
    end

    test "en un curso archivado no se fija", %{admin: admin, course: course} do
      teacher = member(course, "teacher")
      {:ok, post} = publish(teacher, course, "Uno")

      {:ok, _} =
        Actions.run(Amauta.Courses.Actions.ArchiveCourse, admin, %{"course_id" => course.id})

      assert {:error, :archived} = pin(teacher, post)
    end
  end

  # Muchas respuestas de una vez, con fechas crecientes (sin pasar por la
  # acción: acá importa el volumen, no el flujo).
  defp bulk_replies(scope, post, count, parent \\ nil) do
    author = scope.user.id
    start = DateTime.utc_now()

    rows =
      for i <- 1..count do
        at = DateTime.add(start, i, :second)

        %{
          id: Ecto.UUID.generate(),
          post_id: post.id,
          parent_id: parent && parent.id,
          author_id: author,
          body: %{
            "type" => "doc",
            "content" => [
              %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "R#{i}"}]}
            ]
          },
          inserted_at: at,
          updated_at: at
        }
      end

    Amauta.Repo.insert_all(Amauta.Feed.Reply, rows, Amauta.Tenancy.opts(scope))
  end

  # Consultas que hace `fun` en este proceso.
  defp count_queries(fun) do
    ref = make_ref()
    me = self()

    :telemetry.attach(
      inspect(ref),
      [:amauta, :repo, :query],
      fn _event, _measure, _meta, _ -> if self() == me, do: send(me, {ref, :query}) end,
      nil
    )

    fun.()
    :telemetry.detach(inspect(ref))
    count_messages(ref, 0)
  end

  defp count_messages(ref, n) do
    receive do
      {^ref, :query} -> count_messages(ref, n + 1)
    after
      0 -> n
    end
  end

  describe "hilos largos" do
    test "se muestran las últimas respuestas, con los conteos del hilo completo", %{
      course: course
    } do
      teacher = member(course, "teacher")
      {:ok, post} = publish(teacher, course, "Consultas")
      bulk_replies(teacher, post, 200)

      shown = Feed.get_visible(teacher, course, post.id)
      assert shown.reply_count == 200 and shown.top_reply_count == 200
      assert Enum.map(shown.replies, &Amauta.RichText.to_text(&1.body)) == ~w(R198 R199 R200)

      # «Ver anteriores» agranda la ventana.
      wider = Feed.get_visible(teacher, course, post.id, windows: %{post.id => 23})
      assert length(wider.replies) == 23
      assert List.last(wider.replies).body == List.last(shown.replies).body
    end

    test "las anidadas también: las últimas y cuántas hay", %{course: course} do
      teacher = member(course, "teacher")
      {:ok, post} = publish(teacher, course, "Consultas")
      {:ok, top} = reply(teacher, post, "Primera")
      bulk_replies(teacher, post, 50, top)

      [shown] = Feed.get_visible(teacher, course, post.id).replies
      assert shown.child_count == 50
      assert Enum.map(shown.children, &Amauta.RichText.to_text(&1.body)) == ~w(R49 R50)

      [wider] = Feed.get_visible(teacher, course, post.id, windows: %{top.id => 22}).replies
      assert length(wider.children) == 22
      assert Feed.get_visible(teacher, course, post.id).reply_count == 51
    end

    test "cargar el tablón cuesta lo mismo con 3 o con 300 respuestas", %{course: course} do
      teacher = member(course, "teacher")
      {:ok, small} = publish(teacher, course, "Chico")
      bulk_replies(teacher, small, 3)
      small_cost = count_queries(fn -> Feed.list_posts(teacher, course) end)

      {:ok, big} = publish(teacher, course, "Grande")
      {:ok, top} = reply(teacher, big, "Hilo")
      bulk_replies(teacher, big, 300)
      bulk_replies(teacher, big, 100, top)

      assert count_queries(fn -> Feed.list_posts(teacher, course) end) == small_cost

      [big_shown, _small] = Feed.list_posts(teacher, course)
      assert length(big_shown.replies) == 3
    end

    test "las publicaciones se traen de a una página, con cursor", %{course: course} do
      teacher = member(course, "teacher")
      total = Feed.page_size() + 5
      for i <- 1..total, do: {:ok, _} = publish(teacher, course, "P#{i}")

      first = Feed.list_posts(teacher, course)
      assert length(first) == Feed.page_size()

      rest = Feed.list_posts(teacher, course, %{}, before: List.last(first))
      assert length(rest) == 5
      assert MapSet.disjoint?(MapSet.new(first, & &1.id), MapSet.new(rest, & &1.id))
    end
  end
end
