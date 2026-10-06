defmodule AmautaWeb.PeopleLiveTest do
  @moduledoc "Pantallas de personas: directorio, alta, importación y exportación."
  use AmautaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.Accounts
  alias AmautaWeb.Paths

  defp log_in_as(conn, role) do
    user = user_fixture()
    assign!(user, role, :institution)
    {log_in_user(conn, user), user}
  end

  describe "directorio" do
    test "lista, busca y da de alta", %{conn: conn} do
      {conn, _admin} = log_in_as(conn, "institution_admin")
      other = user_fixture(first_name: "Valentina", last_name: "Quispe")

      {:ok, view, html} = live(conn, Paths.people(institution()))
      assert html =~ other.email

      view |> form("#filters", %{"q" => "quispe"}) |> render_change()
      assert_patch(view, Paths.people(institution(), %{"q" => "quispe"}))
      assert has_element?(view, "#person-#{other.id}")

      {:ok, view, _html} = live(conn, Paths.new_person(institution()))

      view
      |> form("#person_form",
        person: %{first_name: "Ana", last_name: "Pérez", email: "ana@example.test"}
      )
      |> render_submit()

      assert %{status: "invited"} = Accounts.get_user_by_email(institution(), "ana@example.test")
    end

    test "suspende desde la tabla", %{conn: conn} do
      {conn, _admin} = log_in_as(conn, "institution_admin")
      other = user_fixture()

      {:ok, view, _html} = live(conn, Paths.people(institution()))
      view |> element(~s(#person-#{other.id} [phx-click="suspend"])) |> render_click()

      assert %{status: "suspended"} = Accounts.get_user!(institution(), other.id)
    end

    test "sin permiso para ver, prohibido", %{conn: conn} do
      {conn, _user} = log_in_as(conn, "student")

      assert_raise AmautaWeb.ForbiddenError, fn -> live(conn, Paths.people(institution())) end
    end
  end

  describe "importación" do
    test "lee, simula e importa", %{conn: conn} do
      {conn, _admin} = log_in_as(conn, "institution_admin")
      {:ok, view, _html} = live(conn, Paths.import_people(institution()))

      csv = "nombre;apellido;email\nAna;Pérez;ana@x.test\nBeto;;mal\n"

      file =
        file_input(view, "#upload_form", :csv, [
          %{name: "personas.csv", content: csv, type: "text/csv"}
        ])

      render_upload(file, "personas.csv")
      view |> form("#upload_form") |> render_submit()

      assert has_element?(view, "#mapping_form")
      assert render(view) =~ "data:text/csv"

      view |> element("button[phx-click=apply]") |> render_click()

      assert Accounts.get_user_by_email(institution(), "ana@x.test")
      refute Accounts.get_user_by_email(institution(), "mal")
    end
  end

  describe "exportación" do
    test "descarga el CSV con BOM", %{conn: conn} do
      {conn, admin} = log_in_as(conn, "institution_admin")

      conn = get(conn, Paths.export_people(institution(), %{}))
      assert <<0xEF, 0xBB, 0xBF, body::binary>> = response(conn, 200)
      assert body =~ admin.email
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/csv"
    end
  end
end
