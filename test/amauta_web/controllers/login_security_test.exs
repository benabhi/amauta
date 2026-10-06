defmodule AmautaWeb.LoginSecurityTest do
  @moduledoc """
  Seguridad del inicio de sesión vista desde la web: bloqueo por intentos,
  avisos por email y proveedores de identidad (RF-AUT-006 y RF-AUT-008).
  """
  # Sincrónico: enciende el limitador, que es global.
  use AmautaWeb.ConnCase, async: false
  use Oban.Testing, repo: Amauta.Repo, prefix: "global"

  import Amauta.AccountsFixtures

  alias Amauta.Accounts
  alias Amauta.Accounts.{LoginThrottle, SecurityEmailWorker}
  alias AmautaWeb.Paths

  setup do
    Application.put_env(:amauta, LoginThrottle, enabled: true)
    LoginThrottle.reset()

    on_exit(fn ->
      LoginThrottle.reset()
      Application.put_env(:amauta, LoginThrottle, enabled: false)
    end)

    %{user: user_fixture() |> set_password()}
  end

  defp attempt(conn, email, password) do
    post(conn, Paths.log_in(institution()), %{
      "user" => %{"email" => email, "password" => password}
    })
  end

  test "después de cinco fallos, ni la contraseña correcta entra", %{conn: conn, user: user} do
    for _ <- 1..5, do: attempt(conn, user.email, "incorrecta")

    conn = attempt(conn, user.email, valid_user_password())
    assert redirected_to(conn) == Paths.log_in(institution())
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many failed attempts"
  end

  test "al bloquearse, se le avisa a la persona por email", %{conn: conn, user: user} do
    for _ <- 1..5, do: attempt(conn, user.email, "incorrecta")

    assert_enqueued(
      worker: SecurityEmailWorker,
      args: %{"user_id" => user.id, "kind" => "account_locked"}
    )
  end

  test "con una cuenta que no existe, la respuesta es la misma y no se envía nada",
       %{conn: conn} do
    conn = attempt(conn, "nadie@example.test", "incorrecta")
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"

    for _ <- 1..5, do: attempt(build_conn(), "nadie@example.test", "incorrecta")
    refute_enqueued(worker: SecurityEmailWorker)
  end

  describe "dispositivos" do
    defp log_in_from(conn, user, agent) do
      conn
      |> put_req_header("user-agent", agent)
      |> attempt(user.email, valid_user_password())
    end

    test "el primer dispositivo no genera aviso; uno nuevo, sí", %{conn: conn, user: user} do
      # El fixture entró con el enlace mágico, sin dispositivo registrado.
      log_in_from(conn, user, "Firefox en Linux")
      refute_enqueued(worker: SecurityEmailWorker)

      log_in_from(build_conn(), user, "Firefox en Linux")
      refute_enqueued(worker: SecurityEmailWorker)

      log_in_from(build_conn(), user, "Safari en iPhone")

      assert_enqueued(
        worker: SecurityEmailWorker,
        args: %{"kind" => "new_device", "user_agent" => "Safari en iPhone"}
      )
    end

    test "el aviso llega por email en el idioma de la persona", %{user: user} do
      assert :ok =
               perform_job(SecurityEmailWorker, %{
                 "institution_id" => institution().id,
                 "user_id" => user.id,
                 "kind" => "new_device",
                 "user_agent" => "Safari en iPhone"
               })

      assert_received {:email, %{subject: "New sign-in to your account", text_body: body}}
      assert body =~ "Safari en iPhone"
    end
  end

  describe "proveedores de identidad" do
    test "contraseña", %{user: user} do
      assert {:ok, %{id: id}, %{disconnect: []}} =
               Accounts.authenticate(institution(), :password, %{
                 "email" => user.email,
                 "password" => valid_user_password()
               })

      assert id == user.id

      assert {:error, :invalid_credentials} =
               Accounts.authenticate(institution(), :password, %{"email" => user.email})
    end

    test "enlace mágico", %{user: user} do
      token = extract_user_token(&Accounts.deliver_login_instructions(institution(), user, &1))

      assert {:ok, %{id: id}, _} =
               Accounts.authenticate(institution(), :magic_link, %{"token" => token})

      assert id == user.id

      assert {:error, :invalid_credentials} =
               Accounts.authenticate(institution(), :magic_link, %{"token" => token})
    end
  end

  describe "inicio de sesión rápido de desarrollo" do
    test "lista las personas con sus roles y entra con un clic", %{conn: conn, user: user} do
      Amauta.AuthorizationFixtures.assign!(user, "teacher", :institution)

      html = conn |> get(Paths.dev_login(institution())) |> html_response(200)
      assert html =~ Accounts.User.display_name(user)
      assert html =~ "Teacher"

      conn = post(conn, Paths.dev_login(institution(), user))
      assert redirected_to(conn) == Paths.home(institution())
    end
  end
end
