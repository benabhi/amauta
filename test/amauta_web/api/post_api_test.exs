defmodule AmautaWeb.Api.PostApiTest do
  use AmautaWeb.ConnCase, async: true

  import Amauta.Fixtures
  alias Amauta.Accounts

  setup do
    a = institution_fixture("inst_test_a")
    b = institution_fixture("inst_test_b")
    course = course_fixture(a)
    teacher = member_fixture(a, "teacher", course)
    student = member_fixture(a, "student", course)

    %{a: a, b: b, course: course, teacher: teacher, student: student}
  end

  defp authed(conn, institution, user) do
    token = Accounts.generate_api_token(institution, user)

    conn
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-type", "application/vnd.api+json")
    |> put_req_header("accept", "application/vnd.api+json")
  end

  defp posts_path(course), do: "/api/v1/courses/#{course.id}/posts"

  defp post_body(body), do: Jason.encode!(%{data: %{type: "post", attributes: %{body: body}}})

  test "sin token responde 401", %{conn: conn, course: course} do
    assert %{"errors" => _} = conn |> get(posts_path(course)) |> json_response(401)
  end

  test "la docente publica y lista", %{conn: conn, a: a, course: course, teacher: teacher} do
    conn = authed(conn, a, teacher)

    assert %{"data" => %{"id" => id, "attributes" => %{"body" => "Hola"}}} =
             conn |> post(posts_path(course), post_body("Hola")) |> json_response(201)

    assert %{
             "data" => [%{"id" => ^id}],
             "included" => [%{"type" => "user", "attributes" => author}]
           } =
             conn |> get(posts_path(course) <> "?include=author") |> json_response(200)

    assert author["name"] == teacher.name
  end

  test "la estudiante no puede publicar", %{conn: conn, a: a, course: course, student: student} do
    conn = authed(conn, a, student)
    assert conn |> post(posts_path(course), post_body("Hola")) |> json_response(403)
  end

  test "cuerpo vacío responde 400", %{conn: conn, a: a, course: course, teacher: teacher} do
    assert %{"errors" => [%{"source" => %{"pointer" => "/data/attributes/body"}}]} =
             conn
             |> authed(a, teacher)
             |> post(posts_path(course), post_body(""))
             |> json_response(400)
  end

  test "un token de otra institución no alcanza el curso", %{conn: conn, b: b, course: course} do
    admin_b = member_fixture(b, "institution_admin")
    assert conn |> authed(b, admin_b) |> get(posts_path(course)) |> json_response(404)
  end

  test "paridad: cada acción pública del tablón es una ruta de la API", %{conn: conn} do
    spec = conn |> get("/api/v1/open_api") |> response(200) |> Jason.decode!()

    operation_ids =
      for {_path, item} <- spec["paths"], {_verb, op} <- item, is_map(op), do: op["operationId"]

    routed =
      for route <- AshJsonApi.Domain.Info.routes(Amauta.Feed), do: {route.resource, route.action}

    for resource <- Ash.Domain.Info.resources(Amauta.Feed),
        action <- Ash.Resource.Info.actions(resource),
        action.name in [:list, :create] or action.type in [:update, :destroy] do
      assert {resource, action.name} in routed, "falta #{inspect(resource)}.#{action.name}"
    end

    assert length(operation_ids) == length(routed)
  end
end
