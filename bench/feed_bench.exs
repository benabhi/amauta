# Medición del spike (ADR-0003): latencia de listar y publicar en el tablón.
# Uso: bin/dev mix run bench/feed_bench.exs
# Corre en el entorno de desarrollo con el log en :warning; sirve para comparar
# las dos ramas del spike entre sí, no como cifra absoluta.
Logger.configure(level: :warning)

alias Amauta.{Accounts, Authorization, Catalog, Feed, Platform, Scope}

n = System.unique_integer([:positive])
{:ok, institution} = Platform.create_institution(%{slug: "bench#{n}", name: "Bench"})
opts = [tenant: institution, authorize?: false]
course = Catalog.create_course!(%{slug: "bench", name: "Bench"}, opts)
user = Accounts.create_user!(%{name: "Docente", email: "bench@example.test"}, opts)
Authorization.assign_role!(%{user_id: user.id, role: "teacher", course_id: course.id}, opts)
scope = Scope.for_user(institution, user)

list = fn -> {:ok, _} = Feed.list_posts(course.id, scope: scope) end
create = fn -> {:ok, _} = Feed.create_post(%{course_id: course.id, body: "Hola"}, scope: scope) end

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

IO.puts("Ash 3 (#{Application.spec(:ash, :vsn)})")
measure.("listar 50 · serie", list, 1_000, 1)
measure.("listar 50 · 20 concurrentes", list, 2_000, 20)
measure.("publicar · serie", create, 1_000, 1)
measure.("publicar · 20 concurrentes", create, 2_000, 20)
