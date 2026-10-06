defmodule Amauta.Platform.StaffAccountsTest do
  @moduledoc "Cuentas del personal de plataforma y asistente (RF-ADM-001, RF-ROL-009)."
  use Amauta.DataCase, async: true

  import Amauta.PlatformFixtures
  alias Amauta.Platform.{Staff, StaffAccounts}

  @attrs %{name: "Ana Sistemas", email: "ana@instancia.test", password: "una clave muy larga"}

  test "el asistente hace falta solo mientras no hay superadministración" do
    assert StaffAccounts.setup_required?()
    assert {:ok, %Staff{role: "superadmin"}} = StaffAccounts.create_first_superadmin(@attrs)
    refute StaffAccounts.setup_required?()
  end

  test "el asistente no crea una segunda superadministración" do
    staff_fixture()
    assert {:error, :already_set_up} = StaffAccounts.create_first_superadmin(@attrs)
  end

  test "valida la cuenta" do
    assert {:error, changeset} =
             StaffAccounts.create_first_superadmin(%{name: "", email: "x", password: "corta"})

    assert %{name: [_], email: [_], password: [_]} = errors_on(changeset)
  end

  test "la contraseña se guarda con hash y se verifica" do
    staff = staff_fixture(email: "luis@instancia.test")
    refute staff.hashed_password == valid_staff_password()

    assert %Staff{id: id} =
             StaffAccounts.get_staff_by_email_and_password(
               "luis@instancia.test",
               valid_staff_password()
             )

    assert id == staff.id
    refute StaffAccounts.get_staff_by_email_and_password("luis@instancia.test", "incorrecta")
    refute StaffAccounts.get_staff_by_email_and_password("nadie@instancia.test", "x")
  end

  test "las sesiones se emiten, se verifican y se cierran" do
    staff = staff_fixture()
    token = StaffAccounts.generate_session_token(staff)

    assert StaffAccounts.get_staff_by_session_token(token).id == staff.id
    StaffAccounts.delete_session_token(token)
    refute StaffAccounts.get_staff_by_session_token(token)
  end
end
