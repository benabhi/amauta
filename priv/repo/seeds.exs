# Datos de ejemplo del spike: dos instituciones con un curso cada una.
# Uso: bin/dev seed (o bin/dev reset para empezar de cero).
alias Amauta.{Accounts, Authorization, Catalog, Platform, Tenancy}
alias AmautaWeb.Paths

seed = fn slug, name ->
  institution =
    Platform.get_institution_by_slug(slug) ||
      elem(Tenancy.create_institution(%{slug: slug, name: name}), 1)

  course =
    Catalog.get_course_by_slug(institution, "prog1") ||
      elem(Catalog.create_course(institution, %{slug: "prog1", name: "Programación I"}), 1)

  people =
    for {role, email, person} <- [
          {"teacher", "docente@#{slug}.test", "Ada Docente"},
          {"student", "estudiante@#{slug}.test", "Beto Estudiante"}
        ] do
      user =
        case Accounts.create_user(institution, %{name: person, email: email}) do
          {:ok, user} ->
            {:ok, _} =
              Authorization.assign_role(institution, %{
                user_id: user.id,
                role: role,
                course_id: course.id
              })

            user

          {:error, _} ->
            Amauta.Repo.get_by!(Accounts.User, [email: email], Tenancy.opts(institution))
        end

      {role, user}
    end

  IO.puts("\n#{name}")

  for {role, user} <- people do
    feed = Paths.course_feed(institution, course)
    IO.puts("  #{role}: http://localhost:4000#{Paths.dev_login(institution, user, feed)}")
    IO.puts("    token API: #{Accounts.generate_api_token(institution, user)}")
  end

  IO.puts("  curso: #{course.id}")
end

seed.("unsur", "Universidad Nacional del Sur (ejemplo)")
seed.("itec", "Instituto Tecnológico (ejemplo)")
