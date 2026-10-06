defmodule Amauta.PathwaysTest do
  @moduledoc "Trayectos, estados, etapas y responsables (RF-TRA-001, RF-TRA-002, RF-INS-003)."
  use Amauta.DataCase, async: true

  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Actions, Audit, Authorization, Pathways, Scope, Slug}
  alias Amauta.Authorization.Actions.AssignRole
  alias Amauta.Pathways.Pathway

  alias Amauta.Pathways.Actions.{
    AddStage,
    ArchivePathway,
    CreatePathway,
    DeleteStage,
    MoveStage,
    PublishPathway,
    RenameStage,
    ReopenPathway,
    UpdatePathway
  }

  setup do
    admin = member_scope("institution_admin")
    {:ok, pathway} = Actions.run(CreatePathway, admin, %{"name" => "Lic. en Sistemas"})
    %{admin: admin, pathway: pathway}
  end

  defp stage_names(scope, pathway),
    do: scope |> Pathways.list_stages(pathway) |> Enum.map(&{&1.position, &1.name})

  describe "slugs" do
    test "slugify quita tildes y signos" do
      assert Slug.slugify("Lic. en Ciencias de la Educación") == "lic-en-ciencias-de-la-educacion"
      assert Slug.slugify("  Año 1 — Diseño  ") == "ano-1-diseno"
    end

    test "se deriva del nombre y no se repite", %{admin: admin, pathway: pathway} do
      assert pathway.slug == "lic-en-sistemas"
      assert pathway.status == "draft"

      {:ok, again} = Actions.run(CreatePathway, admin, %{"name" => "Lic. en Sistemas"})
      assert again.slug == "lic-en-sistemas-2"
    end

    test "valida el slug y el código propios", %{admin: admin} do
      assert {:error, changeset} =
               Actions.run(CreatePathway, admin, %{"name" => "X", "slug" => "Con Espacios"})

      assert %{slug: ["only lowercase letters, digits and hyphens"]} = errors_on(changeset)

      assert {:error, changeset} =
               Actions.run(CreatePathway, admin, %{"name" => "X", "slug" => "new"})

      assert %{slug: ["is reserved"]} = errors_on(changeset)

      {:ok, _} = Actions.run(CreatePathway, admin, %{"name" => "A", "code" => "LSI"})

      assert {:error, changeset} =
               Actions.run(CreatePathway, admin, %{"name" => "B", "code" => "lsi"})

      assert %{code: ["already in use"]} = errors_on(changeset)
    end
  end

  describe "datos y estados" do
    test "edita y queda auditado", %{admin: admin, pathway: pathway} do
      assert {:ok, %{name: "Licenciatura en Sistemas", code: nil}} =
               Actions.run(UpdatePathway, admin, %{
                 "pathway_id" => pathway.id,
                 "name" => "Licenciatura en Sistemas",
                 "code" => ""
               })

      actions = admin |> Audit.list_events() |> Enum.map(& &1.action)
      assert "pathways.pathway.update" in actions
    end

    test "borrador → publicado → archivado → publicado", %{admin: admin, pathway: pathway} do
      params = %{"pathway_id" => pathway.id}

      assert {:error, :invalid_transition} = Actions.run(ReopenPathway, admin, params)
      assert {:ok, %{status: "published"}} = Actions.run(PublishPathway, admin, params)

      assert {:ok, %{status: "archived", archived_at: %DateTime{}}} =
               Actions.run(ArchivePathway, admin, params)

      assert {:ok, %{status: "published", archived_at: nil}} =
               Actions.run(ReopenPathway, admin, params)
    end

    test "un trayecto archivado es de solo lectura", %{admin: admin, pathway: pathway} do
      {:ok, stage} =
        Actions.run(AddStage, admin, %{"pathway_id" => pathway.id, "name" => "1.er año"})

      {:ok, _} = Actions.run(ArchivePathway, admin, %{"pathway_id" => pathway.id})

      assert {:error, :archived} =
               Actions.run(UpdatePathway, admin, %{"pathway_id" => pathway.id, "name" => "X"})

      assert {:error, :archived} =
               Actions.run(AddStage, admin, %{"pathway_id" => pathway.id, "name" => "2.º año"})

      assert {:error, :archived} = Actions.run(DeleteStage, admin, %{"stage_id" => stage.id})
    end

    test "la lista oculta los archivados salvo que se pidan", %{admin: admin, pathway: pathway} do
      {:ok, other} =
        Actions.run(CreatePathway, admin, %{"name" => "Tecnicatura", "code" => "TUP"})

      {:ok, _} = Actions.run(ArchivePathway, admin, %{"pathway_id" => pathway.id})

      assert [%{id: id}] = Pathways.list_visible(admin)
      assert id == other.id
      assert [%{status: "archived"}] = Pathways.list_visible(admin, %{"status" => "archived"})
      assert [%{code: "TUP"}] = Pathways.list_visible(admin, %{"q" => "tup"})
    end
  end

  describe "etapas" do
    setup %{admin: admin, pathway: pathway} do
      stages =
        for name <- ["1.er año", "2.º año", "3.er año"] do
          {:ok, stage} =
            Actions.run(AddStage, admin, %{"pathway_id" => pathway.id, "name" => name})

          stage
        end

      %{stages: stages}
    end

    test "se agregan al final, en orden", %{admin: admin, pathway: pathway} do
      assert stage_names(admin, pathway) == [{1, "1.er año"}, {2, "2.º año"}, {3, "3.er año"}]
    end

    test "se reordenan y en los extremos no pasa nada", ctx do
      %{admin: admin, pathway: pathway, stages: [first, _second, third]} = ctx

      {:ok, _} = Actions.run(MoveStage, admin, %{"stage_id" => third.id, "direction" => "up"})
      assert stage_names(admin, pathway) == [{1, "1.er año"}, {2, "3.er año"}, {3, "2.º año"}]

      {:ok, _} = Actions.run(MoveStage, admin, %{"stage_id" => first.id, "direction" => "up"})
      assert stage_names(admin, pathway) == [{1, "1.er año"}, {2, "3.er año"}, {3, "2.º año"}]

      assert {:error, changeset} =
               Actions.run(MoveStage, admin, %{"stage_id" => first.id, "direction" => "left"})

      assert %{direction: ["is invalid"]} = errors_on(changeset)
    end

    test "se renombran y se borran sin dejar huecos", ctx do
      %{admin: admin, pathway: pathway, stages: [first, second, _third]} = ctx

      {:ok, _} = Actions.run(RenameStage, admin, %{"stage_id" => second.id, "name" => "Segundo"})
      {:ok, _} = Actions.run(DeleteStage, admin, %{"stage_id" => first.id})

      assert stage_names(admin, pathway) == [{1, "Segundo"}, {2, "3.er año"}]
    end
  end

  describe "responsables" do
    test "la coordinación asignada en el trayecto lo ve y lo edita", ctx do
      %{admin: admin, pathway: pathway} = ctx
      {:ok, other} = Actions.run(CreatePathway, admin, %{"name" => "Otro trayecto"})
      user = user_fixture()

      {:ok, _} =
        Actions.run(AssignRole, admin, %{
          "user_id" => user.id,
          "role" => Pathways.coordinator_role(),
          "scope_type" => "pathway",
          "scope_id" => pathway.id
        })

      assert [{%{id: id}, _assignment_id}] = Pathways.coordinators(admin, pathway)
      assert id == user.id

      coordinator = Scope.for_user(institution(), user)
      assert [%{id: visible}] = Pathways.list_visible(coordinator)
      assert visible == pathway.id

      assert {:ok, _} =
               Actions.run(AddStage, coordinator, %{"pathway_id" => pathway.id, "name" => "1"})

      assert {:error, :forbidden} =
               Actions.run(AddStage, coordinator, %{"pathway_id" => other.id, "name" => "1"})
    end
  end

  describe "matriz rol × acción" do
    # {rol, crear, editar y publicar, estructura, archivar}
    @matrix [
      {"institution_admin", true, true, true, true},
      {"academic_management", false, true, false, false},
      {"pathway_coordinator", false, true, true, true},
      {"teacher", false, false, false, false},
      {"student", false, false, false, false},
      {"observer", false, false, false, false}
    ]

    for {role, create, update, structure, archive} <- @matrix do
      test "#{role}", %{pathway: pathway} do
        scope = member_scope(unquote(role))
        id = pathway.id

        expect = fn allowed, result ->
          if allowed,
            do: assert({:ok, _} = result),
            else: assert({:error, :forbidden} = result)
        end

        expect.(unquote(create), Actions.run(CreatePathway, scope, %{"name" => "Nuevo"}))

        expect.(
          unquote(update),
          Actions.run(UpdatePathway, scope, %{"pathway_id" => id, "name" => "Otro nombre"})
        )

        expect.(unquote(update), Actions.run(PublishPathway, scope, %{"pathway_id" => id}))

        expect.(
          unquote(structure),
          Actions.run(AddStage, scope, %{"pathway_id" => id, "name" => "1"})
        )

        expect.(unquote(archive), Actions.run(ArchivePathway, scope, %{"pathway_id" => id}))
      end
    end
  end

  test "un trayecto inexistente es :not_found", %{admin: admin} do
    assert {:error, :not_found} =
             Actions.run(UpdatePathway, admin, %{"pathway_id" => Ecto.UUID.generate()})
  end

  test "Pathway es un objetivo de permisos con su propio ámbito", %{pathway: pathway} do
    user = user_fixture()
    assign!(user, "pathway_coordinator", {"pathway", pathway.id})
    scope = Scope.for_user(institution(), user)

    assert Authorization.can?(scope, "pathway.update", pathway)
    refute Authorization.can?(scope, "pathway.update", %Pathway{id: Ecto.UUID.generate()})
  end

  test "los trayectos de una institución no se ven desde otra", %{admin: admin} do
    b = Amauta.Fixtures.institution_fixture("inst_test_b")
    admin_b = Scope.for_institution(b)

    assert [_] = Pathways.list_visible(admin)
    assert is_nil(Pathways.get_by_slug(b, "lic-en-sistemas"))
    assert [] = Amauta.Repo.all(Pathway, Amauta.Tenancy.opts(admin_b))
  end
end
