defmodule AmautaWeb.UserLive.LoginTest do
  use AmautaWeb.ConnCase, async: true

  alias AmautaWeb.Paths

  import Phoenix.LiveViewTest
  import Amauta.AccountsFixtures

  describe "login page" do
    test "renders login page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, Paths.log_in(institution()))

      assert html =~ "Log in"
      assert html =~ institution().name
      assert html =~ "Log in with email"
    end
  end

  describe "user login - magic link" do
    test "sends magic link email when user exists", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, Paths.log_in(institution()))

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, Paths.log_in(institution()))

      assert html =~ "If your email is in our system"

      assert Amauta.Repo.get_by!(
               Amauta.Accounts.UserToken,
               [user_id: user.id],
               Amauta.Tenancy.opts(institution())
             ).context ==
               "login"
    end

    test "does not disclose if user is registered", %{conn: conn} do
      {:ok, lv, _html} = live(conn, Paths.log_in(institution()))

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", user: %{email: "idonotexist@example.com"})
        |> render_submit()
        |> follow_redirect(conn, Paths.log_in(institution()))

      assert html =~ "If your email is in our system"
    end
  end

  describe "user login - password" do
    test "redirects if user logs in with valid credentials", %{conn: conn} do
      user = user_fixture() |> set_password()

      {:ok, lv, _html} = live(conn, Paths.log_in(institution()))

      form =
        form(lv, "#login_form_password",
          user: %{email: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == Paths.home(institution())
    end

    test "redirects to login page with a flash error if credentials are invalid", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, Paths.log_in(institution()))

      form =
        form(lv, "#login_form_password", user: %{email: "test@email.com", password: "123456"})

      render_submit(form, %{user: %{remember_me: true}})

      conn = follow_trigger_action(form, conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == Paths.log_in(institution())
    end
  end

  describe "login page of an institution" do
    test "shows the institution name and offers no self-registration", %{conn: conn} do
      {:ok, _lv, html} = live(conn, Paths.log_in(institution()))

      assert html =~ institution().name
      refute html =~ "register"
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "shows login page with email filled in", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, Paths.log_in(institution()))

      assert html =~ "You need to reauthenticate"
      refute html =~ "Register"
      assert html =~ "Log in with email"

      assert html =~
               ~s(<input type="email" name="user[email]" id="login_form_magic_email" value="#{user.email}")
    end
  end
end
