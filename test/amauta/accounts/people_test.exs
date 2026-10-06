defmodule Amauta.Accounts.PeopleTest do
  @moduledoc "Directorio, importación y acciones sobre personas (RF-INS-004, RF-USR-003 y 004)."
  use Amauta.DataCase, async: true
  use Oban.Testing, repo: Amauta.Repo, prefix: "global"

  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Accounts, Actions, Audit}
  alias Amauta.Accounts.{Directory, Import, InvitationWorker, User}

  alias Amauta.Accounts.Actions.{
    CreateUser,
    ImportUsers,
    ReactivateUser,
    ResendInvitation,
    SuspendUser,
    UpdateUser
  }

  setup do
    %{admin: member_scope("institution_admin")}
  end

  describe "directorio" do
    test "busca por nombre o email, sin distinguir mayúsculas", %{admin: admin} do
      user_fixture(first_name: "Valentina", last_name: "Quispe", email: "vale@example.test")
      user_fixture(first_name: "Tomás", last_name: "Mamani", email: "tomi@example.test")

      assert [%{first_name: "Valentina"}] = Directory.list(admin, %{"q" => "QUISPE"}).entries
      assert [%{first_name: "Tomás"}] = Directory.list(admin, %{"q" => "tomi@"}).entries
    end

    test "filtra por estado y por rol", %{admin: admin} do
      {:ok, invited} = Accounts.register_user(admin, valid_user_attributes())
      student = user_fixture()
      assign!(student, "student", :institution)

      invited_id = invited.id
      student_id = student.id
      assert [%{id: ^invited_id}] = Directory.list(admin, %{"status" => "invited"}).entries
      assert [%{id: ^student_id}] = Directory.list(admin, %{"role" => "student"}).entries
    end

    test "pagina de a 50", %{admin: admin} do
      for _ <- 1..55, do: Accounts.register_user(admin, valid_user_attributes())

      first = Directory.list(admin, %{})
      second = Directory.list(admin, %{"page" => "2"})
      assert length(first.entries) == 50
      assert first.total >= 56
      assert length(second.entries) == first.total - 50
    end
  end

  describe "acciones" do
    test "el alta deja a la persona invitada y encola la invitación", %{admin: admin} do
      assert {:ok, %User{status: "invited"} = user} =
               Actions.run(CreateUser, admin, %{
                 "first_name" => "Ana",
                 "last_name" => "Pérez",
                 "email" => "ana@example.test"
               })

      assert_enqueued(worker: InvitationWorker, args: %{"user_id" => user.id})
      assert [%{action: "accounts.user.create"} | _] = Audit.list_events(admin) |> Enum.reverse()
    end

    test "el alta sin invitación no encola nada", %{admin: admin} do
      {:ok, _} =
        Actions.run(CreateUser, admin, %{
          "first_name" => "Ana",
          "last_name" => "Pérez",
          "email" => "ana@example.test",
          "send_invitation" => "false"
        })

      refute_enqueued(worker: InvitationWorker)
    end

    test "la invitación llega y su enlace confirma la cuenta", %{admin: admin} do
      {:ok, user} =
        Actions.run(CreateUser, admin, %{
          "first_name" => "Ana",
          "last_name" => "Pérez",
          "email" => "ana@example.test"
        })

      assert :ok =
               perform_job(InvitationWorker, %{
                 "institution_id" => institution().id,
                 "user_id" => user.id
               })

      assert_received {:email,
                       %{to: [{_, "ana@example.test"}], subject: subject, text_body: body}}

      assert subject =~ institution().name
      [_, token] = Regex.run(~r{/log-in/([\w-]+)}, body)

      assert {:ok, {%User{status: "active"}, _}} =
               Accounts.login_user_by_magic_link(institution(), token)
    end

    test "no se invita a quien ya entró", %{admin: admin} do
      user = user_fixture()

      assert {:cancel, :not_invited} =
               perform_job(InvitationWorker, %{
                 "institution_id" => institution().id,
                 "user_id" => user.id
               })

      assert {:error, :not_invited} =
               Actions.run(ResendInvitation, admin, %{"user_id" => user.id})
    end

    test "edita el perfil", %{admin: admin} do
      user = user_fixture()

      assert {:ok, %{preferred_name: "Tati", timezone: "America/Argentina/Cordoba"}} =
               Actions.run(UpdateUser, admin, %{
                 "user_id" => user.id,
                 "preferred_name" => "Tati",
                 "timezone" => "America/Argentina/Cordoba"
               })

      assert {:error, changeset} =
               Actions.run(UpdateUser, admin, %{"user_id" => user.id, "timezone" => "Marte"})

      assert %{timezone: [_]} = errors_on(changeset)
    end

    test "suspender cierra las sesiones; reactivar devuelve el estado", %{admin: admin} do
      user = user_fixture()
      token = Accounts.generate_user_session_token(admin, user)

      assert {:ok, %{status: "suspended"}} =
               Actions.run(SuspendUser, admin, %{"user_id" => user.id})

      refute Accounts.get_user_by_session_token(admin, token)

      assert {:ok, %{status: "active"}} =
               Actions.run(ReactivateUser, admin, %{"user_id" => user.id})

      {:ok, never} = Accounts.register_user(admin, valid_user_attributes())
      Actions.run(SuspendUser, admin, %{"user_id" => never.id})

      assert {:ok, %{status: "invited"}} =
               Actions.run(ReactivateUser, admin, %{"user_id" => never.id})
    end

    test "nadie se suspende a sí mismo", %{admin: admin} do
      assert {:error, :forbidden} = Actions.run(SuspendUser, admin, %{"user_id" => admin.user.id})
    end

    test "sin permiso de gestión, todo está prohibido" do
      teacher = member_scope("teacher")
      user = user_fixture()

      for {action, params} <- [
            {CreateUser, %{"first_name" => "A", "last_name" => "B", "email" => "a@b.test"}},
            {UpdateUser, %{"user_id" => user.id}},
            {SuspendUser, %{"user_id" => user.id}},
            {ImportUsers, %{"rows" => [%{"email" => "x@y.test"}]}}
          ] do
        assert {:error, :forbidden} = Actions.run(action, teacher, params)
      end
    end
  end

  describe "importación" do
    test "lee coma o punto y coma, con o sin BOM" do
      assert {:ok,
              %{headers: ["nombre", "apellido", "email"], rows: [["Ana", "Pérez", "ana@x.test"]]}} =
               Import.parse("nombre,apellido,email\nAna,Pérez,ana@x.test\n")

      assert {:ok, %{rows: [["Ana", "Pérez", "ana@x.test"]]}} =
               Import.parse(
                 <<0xEF, 0xBB, 0xBF>> <> "nombre;apellido;email\r\nAna;Pérez;ana@x.test\r\n"
               )
    end

    test "rechaza archivos vacíos o que no son UTF-8" do
      assert {:error, :empty} = Import.parse("  \n")
      assert {:error, :not_utf8} = Import.parse(<<"nombre\n", 0xF1, 0xFF>>)
    end

    test "reconoce los encabezados en español e inglés" do
      assert %{first_name: 0, last_name: 1, email: 2, preferred_name: 3} =
               Import.guess_mapping([
                 "Nombre",
                 "Apellidos",
                 "Correo electrónico",
                 "Nombre preferido"
               ])

      assert %{first_name: 1, email: 0} = Import.guess_mapping(["E-mail", "First name"])
    end

    test "simula: nuevas, existentes, errores y repetidas", %{admin: admin} do
      existing = user_fixture()

      {:ok, csv} =
        Import.parse("""
        nombre,apellido,email
        Ana,Pérez,ana@x.test
        Beto,Gómez,#{existing.email}
        ,Sin Nombre,sin-nombre@x.test
        Carla,Ruiz,no-es-un-email
        Ana,Otra,ANA@x.test
        """)

      plan = Import.plan(admin, csv.rows, Import.guess_mapping(csv.headers))

      assert [:create, :exists, :error, :error, :error] = Enum.map(plan, & &1.status)
      assert [2, 3, 4, 5, 6] = Enum.map(plan, & &1.line)
      assert %{create: 1, exists: 1, error: 3} = Import.summary(plan)

      report = Import.error_report(plan)
      assert report =~ "line,email,errors"
      assert report =~ "no-es-un-email"
      assert report =~ "ANA@x.test"
    end

    test "aplica: crea las nuevas, saltea las existentes, audita e invita", %{admin: admin} do
      existing = user_fixture()

      rows = [
        %{"first_name" => "Ana", "last_name" => "Pérez", "email" => "ana@x.test"},
        %{"first_name" => "Beto", "last_name" => "Gómez", "email" => existing.email}
      ]

      assert {:ok, %{created: [%User{email: "ana@x.test"}], skipped: 1}} =
               Actions.run(ImportUsers, admin, %{"rows" => rows})

      assert_enqueued(worker: InvitationWorker)

      assert %{action: "accounts.user.import", metadata: %{"created" => 1, "skipped" => 1}} =
               List.last(Audit.list_events(admin))
    end

    test "si una fila falla, no se importa ninguna", %{admin: admin} do
      rows = [
        %{"first_name" => "Ana", "last_name" => "Pérez", "email" => "ana@x.test"},
        %{"first_name" => "", "last_name" => "", "email" => "mal"}
      ]

      assert {:error, %Ecto.Changeset{}} = Actions.run(ImportUsers, admin, %{"rows" => rows})
      refute Accounts.get_user_by_email(admin, "ana@x.test")
    end
  end
end
