defmodule AmautaWeb.PathwaysLiveTest do
  @moduledoc "Pantallas de períodos y trayectos."
  use AmautaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Actions, Pathways, Periods}
  alias Amauta.Pathways.Actions.{AddStage, CreatePathway}
  alias AmautaWeb.Paths

  defp log_in_as(conn, role, scope \\ :institution) do
    user = user_fixture()
    assign!(user, role, scope)
    {log_in_user(conn, user), user}
  end

  defp create_pathway(name) do
    {:ok, pathway} =
      Actions.run(CreatePathway, member_scope("institution_admin"), %{"name" => name})

    pathway
  end

  describe "períodos" do
    test "crea un período y lo marca como actual", %{conn: conn} do
      {conn, _admin} = log_in_as(conn, "institution_admin")

      {:ok, view, _html} = live(conn, Paths.new_period(institution()))

      view
      |> form("#period_form",
        period: %{name: "2027 · 1C", starts_on: "2027-03-01", ends_on: "2027-07-15"}
      )
      |> render_submit()

      [period] = Periods.list(institution())
      assert has_element?(view, "#period-#{period.id}", "2027 · 1C")

      view |> element(~s(#period-#{period.id} [phx-click="set_current"])) |> render_click()
      assert Periods.current(institution()).id == period.id
    end

    test "muestra los errores del formulario", %{conn: conn} do
      {conn, _admin} = log_in_as(conn, "institution_admin")
      {:ok, view, _html} = live(conn, Paths.new_period(institution()))

      html =
        view
        |> form("#period_form",
          period: %{name: "Mal", starts_on: "2027-03-01", ends_on: "2027-01-01"}
        )
        |> render_submit()

      assert html =~ "must be after the start"
    end

    test "sin permiso, prohibido", %{conn: conn} do
      {conn, _user} = log_in_as(conn, "teacher")
      assert_raise AmautaWeb.ForbiddenError, fn -> live(conn, Paths.periods(institution())) end
    end
  end

  describe "lista de trayectos" do
    test "crea un trayecto y lleva a su detalle", %{conn: conn} do
      {conn, _admin} = log_in_as(conn, "institution_admin")
      {:ok, view, _html} = live(conn, Paths.new_pathway(institution()))

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("#pathway_form", pathway: %{name: "Lic. en Sistemas", code: "LSI"})
               |> render_submit()

      assert to == "/#{institution().slug}/pathways/lic-en-sistemas"
    end

    test "busca por nombre o código", %{conn: conn} do
      {conn, _admin} = log_in_as(conn, "institution_admin")
      sistemas = create_pathway("Lic. en Sistemas")
      other = create_pathway("Profesorado de Historia")

      {:ok, view, _html} = live(conn, Paths.pathways(institution()))
      assert has_element?(view, "#pathway-#{other.id}")

      view |> form("#filters", %{"q" => "sistemas"}) |> render_change()
      assert has_element?(view, "#pathway-#{sistemas.id}")
      refute has_element?(view, "#pathway-#{other.id}")
    end

    test "la docencia sin trayectos ve la lista vacía y no puede crear", %{conn: conn} do
      create_pathway("Lic. en Sistemas")
      {conn, _user} = log_in_as(conn, "teacher")

      {:ok, view, _html} = live(conn, Paths.pathways(institution()))
      refute has_element?(view, "#pathways")
      refute has_element?(view, ~s(a[href="#{Paths.new_pathway(institution())}"]))

      assert_raise AmautaWeb.ForbiddenError, fn ->
        live(conn, Paths.new_pathway(institution()))
      end
    end
  end

  describe "detalle del trayecto" do
    test "agrega, reordena y borra etapas", %{conn: conn} do
      {conn, _admin} = log_in_as(conn, "institution_admin")
      pathway = create_pathway("Lic. en Sistemas")

      {:ok, view, _html} = live(conn, Paths.pathway(institution(), pathway))

      for name <- ["1.er año", "2.º año"] do
        view |> form("#stage_form", stage: %{name: name}) |> render_submit()
      end

      [first, second] = Pathways.list_stages(institution(), pathway)
      assert has_element?(view, "#stage-#{first.id}", "1.er año")

      view
      |> element(~s(#stage-#{second.id} [phx-click="move_stage"][phx-value-direction="up"]))
      |> render_click()

      assert [%{id: id}, _] = Pathways.list_stages(institution(), pathway)
      assert id == second.id

      view |> element(~s(#stage-#{first.id} [phx-click="delete_stage"])) |> render_click()
      refute has_element?(view, "#stage-#{first.id}")
    end

    test "renombra una etapa", %{conn: conn} do
      {conn, admin} = log_in_as(conn, "institution_admin")
      pathway = create_pathway("Lic. en Sistemas")
      scope = Amauta.Scope.for_user(institution(), admin)
      {:ok, stage} = Actions.run(AddStage, scope, %{"pathway_id" => pathway.id, "name" => "Uno"})

      {:ok, view, _html} = live(conn, Paths.pathway(institution(), pathway))
      view |> element(~s(#stage-#{stage.id} [phx-click="edit_stage"])) |> render_click()
      view |> form("#stage_form", stage: %{name: "Primer año"}) |> render_submit()

      assert has_element?(view, "#stage-#{stage.id}", "Primer año")
    end

    test "edita, publica, archiva y reabre", %{conn: conn} do
      {conn, _admin} = log_in_as(conn, "institution_admin")
      pathway = create_pathway("Lic. en Sistemas")

      {:ok, view, _html} = live(conn, Paths.edit_pathway(institution(), pathway))

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("#pathway_form", pathway: %{name: "Licenciatura", slug: "licenciatura"})
               |> render_submit()

      assert to =~ "/pathways/licenciatura"

      {:ok, view, _html} = live(conn, to)
      view |> element(~s(button[phx-click="publish"])) |> render_click()
      assert Pathways.get(institution(), pathway.id).status == "published"

      view |> element(~s(button[phx-click="archive"])) |> render_click()
      assert Pathways.get(institution(), pathway.id).status == "archived"
      refute has_element?(view, "#stage_form")

      view |> element(~s(button[phx-click="reopen"])) |> render_click()
      assert Pathways.get(institution(), pathway.id).status == "published"
    end

    test "agrega y quita responsables", %{conn: conn} do
      {conn, _admin} = log_in_as(conn, "institution_admin")
      pathway = create_pathway("Lic. en Sistemas")
      person = user_fixture(first_name: "Valentina", last_name: "Quispe")

      {:ok, view, _html} = live(conn, Paths.pathway(institution(), pathway))

      view |> form("#coordinator_search", %{"q" => "quispe"}) |> render_change()

      view
      |> element(~s(#people_results [phx-click="add_coordinator"][phx-value-id="#{person.id}"]))
      |> render_click()

      assert has_element?(view, "#coordinator-#{person.id}")
      assert [_] = Pathways.coordinators(institution(), pathway)

      view
      |> element(~s(#coordinator-#{person.id} [phx-click="remove_coordinator"]))
      |> render_click()

      refute has_element?(view, "#coordinator-#{person.id}")
    end

    test "la coordinación ve su trayecto pero no otros", %{conn: conn} do
      pathway = create_pathway("Lic. en Sistemas")
      other = create_pathway("Otro")
      {conn, _user} = log_in_as(conn, "pathway_coordinator", {"pathway", pathway.id})

      {:ok, view, _html} = live(conn, Paths.pathways(institution()))
      assert has_element?(view, "#pathway-#{pathway.id}")
      refute has_element?(view, "#pathway-#{other.id}")

      assert {:ok, _view, _html} = live(conn, Paths.pathway(institution(), pathway))

      assert_raise AmautaWeb.ForbiddenError, fn ->
        live(conn, Paths.pathway(institution(), other))
      end
    end

    test "un slug inexistente es 404", %{conn: conn} do
      {conn, _admin} = log_in_as(conn, "institution_admin")

      assert_raise AmautaWeb.NotFoundError, fn ->
        live(conn, Paths.pathway(institution(), %{slug: "no-existe"}))
      end
    end
  end
end
