defmodule AmautaWeb.NotificationsLiveTest do
  @moduledoc "Campana, centro de notificaciones, preferencias y baja de los emails (RF-NOT-001, 002 y 004, RF-EML-009)."
  use AmautaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Amauta.AccountsFixtures

  alias Amauta.{Notifications, Scope}
  alias AmautaWeb.{NotificationLinks, Paths}

  setup do
    user = user_fixture()
    %{user: user, scope: Scope.for_user(institution(), user)}
  end

  defp notify(user, title) do
    Notifications.deliver(institution(), "feed.post_published", [{user.id, "role:student"}], %{
      data: %{"title" => title},
      group_key: "test:#{title}"
    })
  end

  test "la campana cuenta las no leídas y se actualiza en tiempo real", %{conn: conn, user: user} do
    {:ok, view, _html} = conn |> log_in_user(user) |> live(Paths.home(institution()))
    refute has_element?(view, "#notification-bell [data-unread]")

    notify(user, "Aviso")
    _ = render(view)
    assert has_element?(view, "#notification-bell [data-unread]", "1")
  end

  test "el centro lista, dice por qué y marca como leído", %{conn: conn, user: user, scope: scope} do
    notify(user, "Programa")
    notify(user, "Cronograma")
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, Paths.notifications(institution()))
    assert has_element?(view, "#notifications li", "Programa")
    assert has_element?(view, "#notifications li", "Because you are a student")

    [first | _] = Notifications.list(scope).entries

    view
    |> element(~s(#notification-#{first.id} button[phx-click="open"]))
    |> render_click()

    assert Notifications.unread_count(scope) == 1

    {:ok, view, _html} = live(conn, Paths.notifications(institution()))
    view |> element("#notifications-read-all") |> render_click()
    assert Notifications.unread_count(scope) == 0
  end

  test "las preferencias se eligen por evento y canal", %{conn: conn, user: user, scope: scope} do
    {:ok, view, _html} =
      conn |> log_in_user(user) |> live(Paths.notification_settings(institution()))

    view |> element("#pref-feed\\.post_published-email") |> render_click()
    assert %{{"feed.post_published", "email"} => false} = Notifications.preferences(scope)
  end

  test "la baja con un clic apaga los emails, sin sesión", %{conn: conn, user: user, scope: scope} do
    token = NotificationLinks.unsubscribe_token(institution(), user)

    conn = get(conn, Paths.unsubscribe(institution(), token))
    assert html_response(conn, 200) =~ "Stop these emails"

    # El cliente de correo hace el POST directo (RFC 8058), sin token CSRF.
    conn =
      post(build_conn(), Paths.unsubscribe(institution(), token), %{
        "List-Unsubscribe" => "One-Click"
      })

    assert html_response(conn, 200) =~ "you will not receive notification emails"

    assert Enum.all?(Notifications.preferences(scope), fn
             {{_event, "email"}, enabled} -> not enabled
             _ -> true
           end)

    conn = post(build_conn(), Paths.unsubscribe(institution(), "no-vale"))
    assert html_response(conn, 404) =~ "not valid"
  end
end
