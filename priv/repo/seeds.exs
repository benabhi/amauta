# Datos de ejemplo del spike: dos instituciones con un curso cada una.
# Uso: bin/dev seed (o bin/dev reset para empezar de cero).
require Ash.Query
alias Amauta.{Accounts, Authorization, Catalog, Platform}
alias AmautaWeb.Paths

seed = fn slug, name ->
  institution =
    Platform.get_institution_by_slug!(slug) ||
      Platform.create_institution!(%{slug: slug, name: name})

  opts = [tenant: institution, authorize?: false]

  course =
    Catalog.get_course_by_slug!("prog1", opts) ||
      Catalog.create_course!(%{slug: "prog1", name: "Programación I"}, opts)

  people =
    for {role, email, person} <- [
          {"teacher", "docente@#{slug}.test", "Ada Docente"},
          {"student", "estudiante@#{slug}.test", "Beto Estudiante"}
        ] do
      user =
        case Accounts.create_user(%{name: person, email: email}, opts) do
          {:ok, user} ->
            Authorization.assign_role!(
              %{user_id: user.id, role: role, course_id: course.id},
              opts
            )

            user

          {:error, _} ->
            Accounts.User |> Ash.Query.filter(email == ^email) |> Ash.read_one!(opts)
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
