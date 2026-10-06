# Datos de ejemplo para desarrollo (RNF-DEV-007). Es idempotente.
# Uso: bin/dev seed, o bin/dev reset para empezar de cero.
#
# La contraseña de todas las personas de ejemplo es solo para desarrollo.
alias Amauta.{Accounts, Authorization, Pathways, Periods, Platform, Tenancy}

password = "amauta-dev-1234"

institutions = [
  {"unsur", "Universidad Nacional del Sur (ejemplo)", "UNSur"},
  {"itec", "Instituto Tecnológico (ejemplo)", "ITec"}
]

# Sin cursos todavía, los roles de curso se asignan en toda la institución.
# La coordinación se asigna en el trayecto de ejemplo (más abajo).
people = [
  {"Ada", "Docente", "docente", "teacher"},
  {"Beto", "Estudiante", "estudiante", "student"},
  {"Carla", "Administración", "admin", "institution_admin"},
  {"Dora", "Coordinación", "coordinacion", nil}
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

    if role && Authorization.list_assignments(institution, user.id) == [] do
      {:ok, _} =
        Authorization.create_assignment(institution, %{
          user_id: user.id,
          role: role,
          scope_type: "institution"
        })
    end

    IO.puts("  #{user.email} / #{password} (#{role || "pathway_coordinator en el trayecto"})")
  end

  # Período actual y un trayecto con sus etapas (RF-INS-009, RF-TRA-001).
  unless Periods.current(institution) do
    {:ok, period} =
      Periods.create(institution, %{
        name: "2027 · 1.er cuatrimestre",
        starts_on: ~D[2027-03-01],
        ends_on: ~D[2027-07-15]
      })

    {:ok, _} = Periods.set_current(institution, period)
  end

  pathway =
    Pathways.get_by_slug(institution, "lic-en-sistemas") ||
      with {:ok, pathway} <-
             Pathways.create(institution, %{
               name: "Lic. en Sistemas",
               code: "LSI",
               description: "Trayecto de ejemplo para probar etapas y responsables."
             }) do
        for name <- ["1.er año", "2.º año", "3.er año"],
            do: {:ok, _} = Pathways.add_stage(institution, pathway, %{name: name})

        pathway
      end

  coordinator = Accounts.get_user_by_email(institution, "coordinacion@#{slug}.test")

  if Pathways.coordinators(institution, pathway) == [] do
    {:ok, _} =
      Authorization.create_assignment(institution, %{
        user_id: coordinator.id,
        role: Pathways.coordinator_role(),
        scope_type: "pathway",
        scope_id: pathway.id
      })
  end

  IO.puts(
    "  Trayecto: #{AmautaWeb.Paths.absolute(AmautaWeb.Paths.pathway(institution, pathway))}"
  )
end
