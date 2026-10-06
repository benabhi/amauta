# Medición del spike (ADR-0003): latencia de listar y publicar en el tablón.
# Uso: bin/dev mix run bench/feed_bench.exs
# Corre en el entorno de desarrollo con el log en :warning; sirve para comparar
# las dos ramas del spike entre sí, no como cifra absoluta.
Logger.configure(level: :warning)

alias Amauta.{Accounts, Actions, Authorization, Catalog, Scope, Tenancy}
alias Amauta.Feed.Actions.{CreatePost, ListPosts}

n = System.unique_integer([:positive])
{:ok, institution} = Tenancy.create_institution(%{slug: "bench#{n}", name: "Bench"})
{:ok, course} = Catalog.create_course(institution, %{slug: "bench", name: "Bench"})
{:ok, user} = Accounts.create_user(institution, %{name: "Docente", email: "bench@example.test"})

{:ok, _} =
  Authorization.assign_role(institution, %{user_id: user.id, role: "teacher", course_id: course.id})

scope = Scope.for_user(institution, user)

list = fn -> {:ok, _} = Actions.run(ListPosts, scope, %{"course_id" => course.id}) end

create = fn ->
  {:ok, _} = Actions.run(CreatePost, scope, %{"course_id" => course.id, "body" => "Hola"})
end

measure = fn label, fun, iterations, concurrency ->
  for _ <- 1..20, do: fun.()

  {total_us, samples} =
    :timer.tc(fn ->
      1..iterations
      |> Task.async_stream(fn _ -> elem(:timer.tc(fun), 0) end,
        max_concurrency: concurrency,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, us} -> us end)
    end)

  sorted = Enum.sort(samples)
  pct = fn p -> Enum.at(sorted, round(p * (length(sorted) - 1))) / 1000 end
  rps = round(iterations / (total_us / 1_000_000))

  IO.puts(
    String.pad_trailing(label, 28) <>
      "p50 #{pct.(0.5)} ms · p95 #{pct.(0.95)} ms · #{rps} op/s"
  )
end

for _ <- 1..50, do: create.()

IO.puts("Contextos con Ecto (#{Application.spec(:ecto, :vsn)})")
measure.("listar 50 · serie", list, 1_000, 1)
measure.("listar 50 · 20 concurrentes", list, 2_000, 20)
measure.("publicar · serie", create, 1_000, 1)
measure.("publicar · 20 concurrentes", create, 2_000, 20)
