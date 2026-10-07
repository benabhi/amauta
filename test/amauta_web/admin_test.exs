defmodule AmautaWeb.AdminTest do
  @moduledoc "Administración de la instancia (RF-ADM-001, 002 y 003)."
  use AmautaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Amauta.PlatformFixtures
  import Amauta.AccountsFixtures, only: [institution: 0]

  alias Amauta.{Accounts, Audit, Authorization, Platform}
  alias Amauta.Platform.Administration

  describe "asistente de primera ejecución" do
    test "crea la superadministración y lleva a iniciar sesión", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/setup")

      result =
        view
        |> form("#setup_form",
          staff: %{
            name: "Ana Sistemas",
            email: "ana@instancia.test",
            password: "una clave muy larga"
          }
        )
        |> render_submit()

      assert {:error, {:live_redirect, %{to: "/admin/log-in"}}} = result
      refute Amauta.Platform.StaffAccounts.setup_required?()
    end

    test "una vez configurada la instancia, no se puede volver a usar", %{conn: conn} do
      staff_fixture()
      assert {:error, {:live_redirect, %{to: "/admin"}}} = live(conn, ~p"/setup")
    end
  end

  describe "acceso" do
    setup do
      %{staff: staff_fixture(email: "ana@instancia.test")}
    end

    test "sin sesión, /admin y la telemetría piden iniciar sesión", %{conn: conn} do
      assert conn |> get(~p"/admin") |> redirected_to() == ~p"/admin/log-in"
      assert conn |> get(~p"/admin/dashboard") |> redirected_to() == ~p"/admin/log-in"
    end

    test "inicia sesión con email y contraseña", %{conn: conn} do
      conn =
        post(conn, ~p"/admin/log-in", %{
          "staff" => %{"email" => "ana@instancia.test", "password" => valid_staff_password()}
        })

      assert redirected_to(conn) == ~p"/admin"
      assert conn |> recycle() |> get(~p"/admin") |> html_response(200) =~ "Instituciones"
    end

    test "rechaza una contraseña incorrecta", %{conn: conn} do
      conn =
        post(conn, ~p"/admin/log-in", %{
          "staff" => %{"email" => "ana@instancia.test", "password" => "incorrecta"}
        })

      assert redirected_to(conn) == ~p"/admin/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "contraseña"
    end

    test "una sesión de una institución no da acceso a /admin", %{conn: conn} do
      user = Amauta.AccountsFixtures.user_fixture()
      Amauta.AuthorizationFixtures.assign!(user, "institution_admin", :institution)
      conn = log_in_user(conn, user)

      assert conn |> get(~p"/admin") |> redirected_to() == ~p"/admin/log-in"
    end

    test "la telemetría abre con sesión de personal", %{conn: conn, staff: staff} do
      conn = conn |> log_in_staff(staff) |> get(~p"/admin/dashboard")
      assert redirected_to(conn) =~ "/admin/dashboard/"
    end
  end

  describe "instituciones" do
    setup %{conn: conn} do
      staff = staff_fixture()
      %{conn: log_in_staff(conn, staff), staff: staff, institution: institution()}
    end

    test "lista las instituciones", %{conn: conn, institution: i} do
      {:ok, _view, html} = live(conn, ~p"/admin")
      assert html =~ i.name
    end

    test "asigna la administración: alta, rol, invitación y auditoría",
         %{conn: conn, institution: i, staff: staff} do
      {:ok, view, _html} = live(conn, ~p"/admin/institutions/#{i.id}")

      view
      |> form("#admin_form",
        admin: %{first_name: "Carla", last_name: "Quispe", email: "carla@inst.test"}
      )
      |> render_submit()

      user = Accounts.get_user_by_email(i, "carla@inst.test")
      assert user.first_name == "Carla"

      assert [%{role: "institution_admin", scope_type: "institution"}] =
               Authorization.list_assignments(i, user.id)

      assert_received {:email, %{to: [{_, "carla@inst.test"}]}}

      assert [%{action: "authorization.role_assignment.create", metadata: metadata}] =
               Audit.list_events(i)

      assert metadata["platform_staff_id"] == staff.id

      assert [%{action: "platform.institution_admin.assign"}] = Administration.list_events()
      assert render(view) =~ "carla@inst.test"
    end

    test "si la persona ya existe, no la duplica", %{institution: i, staff: staff} do
      existing = Amauta.AccountsFixtures.user_fixture()

      {:ok, user} =
        Administration.assign_admin(staff, i, %{"email" => existing.email}, &"/x/#{&1}")

      assert user.id == existing.id
    end

    test "quita la administración", %{institution: i, staff: staff} do
      {:ok, user} =
        Administration.assign_admin(
          staff,
          i,
          %{"first_name" => "Carla", "last_name" => "Q", "email" => "carla@inst.test"},
          &"/x/#{&1}"
        )

      [{_, assignment}] = Administration.list_admins(i)
      assert :ok = Administration.revoke_admin(staff, i, assignment.id)
      assert [] = Authorization.list_assignments(i, user.id)
      assert {:error, :not_found} = Administration.revoke_admin(staff, i, assignment.id)
    end

    test "suspende y reactiva desde su página", %{conn: conn, institution: i} do
      {:ok, view, _html} = live(conn, ~p"/admin/institutions/#{i.id}")

      render_click(view, "toggle_status")
      assert Platform.get_institution!(i.id).status == "suspended"

      render_click(view, "toggle_status")
      assert Platform.get_institution!(i.id).status == "active"

      assert [_, _] =
               Enum.filter(
                 Administration.list_events(),
                 &(&1.action in ["platform.institution.suspend", "platform.institution.activate"])
               )
    end

    test "edita los datos y lo audita", %{conn: conn, institution: i} do
      {:ok, view, _html} = live(conn, ~p"/admin/institutions/#{i.id}")

      view
      |> form("#institution_form", institution: %{name: "Universidad Renombrada"})
      |> render_submit()

      assert Platform.get_institution!(i.id).name == "Universidad Renombrada"

      assert [
               %{
                 action: "platform.institution.update",
                 metadata: %{"name" => "Universidad Renombrada"}
               }
             ] =
               Administration.list_events()
    end
  end
end
