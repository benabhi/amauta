# Datos de ejemplo para desarrollo (RNF-DEV-007). Es idempotente.
# Uso: bin/dev seed, o bin/dev reset para empezar de cero.
#
# La contraseña de todas las personas de ejemplo es solo para desarrollo.
alias Amauta.{Accounts, Authorization, Platform, Tenancy}

password = "amauta-dev-1234"

institutions = [
  {"unsur", "Universidad Nacional del Sur (ejemplo)", "UNSur"},
  {"itec", "Instituto Tecnológico (ejemplo)", "ITec"}
]

# Sin cursos todavía (llegan en H1), los roles de curso se asignan en toda
# la institución.
people = [
  {"Ada", "Docente", "docente", "teacher"},
  {"Beto", "Estudiante", "estudiante", "student"},
  {"Carla", "Administración", "admin", "institution_admin"}
]

# Superadministración de la instancia (solo desarrollo).
staff_email = "superadmin@amauta.test"

unless Amauta.Repo.get_by(Amauta.Platform.Staff, email: staff_email) do
  {:ok, _} =
    Amauta.Platform.StaffAccounts.create_first_superadmin(%{
      name: "Superadministración",
      email: staff_email,
      password: password
    })
end

IO.puts("Administración → http://localhost:4000/admin · #{staff_email} / #{password}")

for {slug, name, short_name} <- institutions do
  institution =
    Platform.get_institution_by_slug(slug) ||
      case Tenancy.create_institution(%{slug: slug, name: name, short_name: short_name}) do
        {:ok, institution} -> institution
        {:error, error} -> raise "could not create #{slug}: #{inspect(error)}"
      end

  IO.puts("\n#{name} → #{AmautaWeb.Paths.absolute(AmautaWeb.Paths.log_in(institution))}")

  for {first_name, last_name, handle, role} <- people do
    email = "#{handle}@#{slug}.test"

    user =
      Accounts.get_user_by_email(institution, email) ||
        with {:ok, user} <-
               Accounts.register_user(institution, %{
                 first_name: first_name,
                 last_name: last_name,
                 email: email
               }),
             user = Amauta.Repo.update!(Accounts.User.confirm_changeset(user)),
             {:ok, {user, _}} <-
               Accounts.update_user_password(institution, user, %{password: password}) do
          user
        end

    if Authorization.list_assignments(institution, user.id) == [] do
      {:ok, _} =
        Authorization.create_assignment(institution, %{
          user_id: user.id,
          role: role,
          scope_type: "institution"
        })
    end

    IO.puts("  #{user.email} / #{password} (#{role})")
  end
end
