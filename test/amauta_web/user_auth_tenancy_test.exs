defmodule AmautaWeb.UserAuthTenancyTest do
  @moduledoc "La autenticación respeta el aislamiento entre instituciones (RNF-SEG-002)."
  use AmautaWeb.ConnCase, async: true

  import Amauta.AccountsFixtures
  import Amauta.Fixtures, only: [institution_fixture: 1]

  alias Amauta.{Accounts, Platform, Repo, Tenancy}
  alias Amauta.Accounts.User
  alias AmautaWeb.{Paths, UserAuth}

  # Siempre primero `inst_test_a` y después `inst_test_b`: los tests en
  # paralelo insertan las mismas filas y un orden distinto produce deadlocks.
  setup do
    institution()
    %{other: institution_fixture("inst_test_b")}
  end

  test "una sesión de una institución no vale en otra", %{conn: conn, other: other} do
    conn = log_in_user(conn, user_fixture())

    assert conn |> get(Paths.home(institution())) |> html_response(200)
    assert conn |> get(Paths.home(other)) |> redirected_to() == Paths.log_in(other)
  end

  test "el token de sesión de una institución no existe en otra", %{other: other} do
    token = Accounts.generate_user_session_token(institution(), user_fixture())

    assert {%User{}, _} = Accounts.get_user_by_session_token(institution(), token)
    assert Accounts.get_user_by_session_token(other, token) == nil
  end

  test "el mismo email puede existir en dos instituciones", %{other: other} do
    user = user_fixture()

    assert {:ok, %User{}} =
             Accounts.register_user(other, valid_user_attributes(email: user.email))
  end

  test "la clave de sesión y la cookie son propias de cada institución", %{other: other} do
    refute UserAuth.session_token_key(institution()) == UserAuth.session_token_key(other)
  end

  test "una persona suspendida no puede iniciar sesión ni usar su sesión", %{conn: conn} do
    user = user_fixture() |> set_password()
    conn = log_in_user(conn, user)

    Repo.update_all(User, [set: [status: "suspended"]], Tenancy.opts(institution()))

    assert conn |> get(Paths.home(institution())) |> redirected_to() ==
             Paths.log_in(institution())

    refute Accounts.get_user_by_email_and_password(
             institution(),
             user.email,
             valid_user_password()
           )
  end

  test "una institución suspendida responde 403", %{conn: conn} do
    {:ok, _} = Platform.suspend_institution(institution())

    assert_error_sent 403, fn -> get(conn, Paths.log_in(institution())) end
  end

  test "una institución inexistente responde 404", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, "/no-existe/log-in") end
  end
end
