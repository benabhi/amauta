defmodule AmautaWeb.UserLive.SettingsTest do
  use AmautaWeb.ConnCase, async: true

  alias AmautaWeb.Paths
  alias AmautaWeb.UserAuth

  alias Amauta.Accounts
  import Phoenix.LiveViewTest
  import Amauta.AccountsFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(Paths.settings(institution()))

      assert html =~ "Change Email"
      assert html =~ "Save Password"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, Paths.settings(institution()))

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == Paths.log_in(institution())
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "redirects if user is not in sudo mode", %{conn: conn} do
      {:ok, conn} =
        conn
        |> log_in_user(user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> live(Paths.settings(institution()))
        |> follow_redirect(
          conn,
          Paths.log_in_return(institution(), Paths.settings(institution()))
        )

      assert conn.resp_body =~ "You must re-authenticate to access this page."
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user email", %{conn: conn, user: user} do
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, Paths.settings(institution()))

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "A link to confirm your email"
      assert Accounts.get_user_by_email(institution(), user.email)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, Paths.settings(institution()))

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "user" => %{"email" => "with spaces"}
        })

      assert result =~ "Change Email"
      assert result =~ "must have the @ sign and no spaces"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, Paths.settings(institution()))

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => user.email}
        })
        |> render_submit()

      assert result =~ "Change Email"
      assert result =~ "did not change"
    end
  end

  describe "update password form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user password", %{conn: conn, user: user} do
      new_password = valid_user_password()

      {:ok, lv, _html} = live(conn, Paths.settings(institution()))

      form =
        form(lv, "#password_form", %{
          "user" => %{
            "email" => user.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      render_submit(form)

      new_password_conn = follow_trigger_action(form, conn)

      assert redirected_to(new_password_conn) == Paths.settings(institution())

      assert get_session(new_password_conn, :user_token) !=
               get_session(conn, UserAuth.session_token_key(institution()))

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Password updated successfully"

      assert Accounts.get_user_by_email_and_password(institution(), user.email, new_password)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, Paths.settings(institution()))

      result =
        lv
        |> element("#password_form")
        |> render_change(%{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, Paths.settings(institution()))

      result =
        lv
        |> form("#password_form", %{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })
        |> render_submit()

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(
            institution(),
            %{user | email: email},
            user.email,
            url
          )
        end)

      %{conn: log_in_user(conn, user), token: token, email: email, user: user}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      {:error, redirect} = live(conn, Paths.confirm_email(institution(), token))

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == Paths.settings(institution())
      assert %{"info" => message} = flash
      assert message == "Email changed successfully."
      refute Accounts.get_user_by_email(institution(), user.email)
      assert Accounts.get_user_by_email(institution(), email)

      # use confirm token again
      {:error, redirect} = live(conn, Paths.confirm_email(institution(), token))
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == Paths.settings(institution())
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      {:error, redirect} = live(conn, Paths.confirm_email(institution(), "oops"))
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == Paths.settings(institution())
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
      assert Accounts.get_user_by_email(institution(), user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, Paths.confirm_email(institution(), token))
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == Paths.log_in(institution())
      assert %{"error" => message} = flash
      assert message == "You must log in to access this page."
    end
  end
end
