defmodule Amauta.PlatformFixtures do
  @moduledoc "Personal de plataforma de prueba."
  alias Amauta.Platform.{Staff, StaffAccounts}
  alias Amauta.Repo

  def valid_staff_password, do: "una clave muy larga"

  def staff_fixture(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    %Staff{role: "superadmin"}
    |> Staff.registration_changeset(
      Enum.into(attrs, %{
        name: "Super Admin #{n}",
        email: "admin#{n}@instancia.test",
        password: valid_staff_password()
      })
    )
    |> Repo.insert!()
  end

  @doc "Inicia la sesión de personal en el conn de prueba."
  def log_in_staff(conn, staff) do
    token = StaffAccounts.generate_session_token(staff)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session("staff_token", token)
  end
end
