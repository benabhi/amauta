defmodule AmautaWeb.UserSessionControllerTest do
  use AmautaWeb.ConnCase, async: true

  alias AmautaWeb.Paths
  alias AmautaWeb.UserAuth

  import Amauta.AccountsFixtures
  alias Amauta.Accounts

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), user: user_fixture()}
  end

  describe "POST /users/log-in - email and password" do
    test "logs the user in", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, Paths.log_in(institution()), %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, UserAuth.session_token_key(institution()))
      assert redirected_to(conn) == Paths.home(institution())

      # Now do a logged in request and assert on the menu
      conn = get(conn, Paths.home(institution()))
      response = html_response(conn, 200)
      assert response =~ Amauta.Accounts.User.display_name(user)
      assert response =~ Paths.settings(institution())
      assert response =~ Paths.log_out(institution())
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, Paths.log_in(institution()), %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_amauta_remember_me_#{institution().id}"]
      assert redirected_to(conn) == Paths.home(institution())
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(Paths.log_in(institution()), %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "redirects to login page with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, Paths.log_in(institution()) <> "?mode=password", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == Paths.log_in(institution())
    end
  end

  describe "POST /users/log-in - magic link" do
    test "logs the user in", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, Paths.log_in(institution()), %{
          "user" => %{"token" => token}
        })

      assert get_session(conn, UserAuth.session_token_key(institution()))
      assert redirected_to(conn) == Paths.home(institution())

      # Now do a logged in request and assert on the menu
      conn = get(conn, Paths.home(institution()))
      response = html_response(conn, 200)
      assert response =~ Amauta.Accounts.User.display_name(user)
      assert response =~ Paths.settings(institution())
      assert response =~ Paths.log_out(institution())
    end

    test "confirms unconfirmed user", %{conn: conn, unconfirmed_user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)
      refute user.confirmed_at

      conn =
        post(conn, Paths.log_in(institution()), %{
          "user" => %{"token" => token},
          "_action" => "confirmed"
        })

      assert get_session(conn, UserAuth.session_token_key(institution()))
      assert redirected_to(conn) == Paths.home(institution())
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "User confirmed successfully."

      assert Accounts.get_user!(institution(), user.id).confirmed_at

      # Now do a logged in request and assert on the menu
      conn = get(conn, Paths.home(institution()))
      response = html_response(conn, 200)
      assert response =~ Amauta.Accounts.User.display_name(user)
      assert response =~ Paths.settings(institution())
      assert response =~ Paths.log_out(institution())
    end

    test "redirects to login page when magic link is invalid", %{conn: conn} do
      conn =
        post(conn, Paths.log_in(institution()), %{
          "user" => %{"token" => "invalid"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "The link is invalid or it has expired."

      assert redirected_to(conn) == Paths.log_in(institution())
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(Paths.log_out(institution()))
      assert redirected_to(conn) == Paths.log_in(institution())
      refute get_session(conn, UserAuth.session_token_key(institution()))
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, Paths.log_out(institution()))
      assert redirected_to(conn) == Paths.log_in(institution())
      refute get_session(conn, UserAuth.session_token_key(institution()))
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
