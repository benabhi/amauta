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
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp posts_path(course), do: "/api/v1/courses/#{course.id}/posts"

  test "sin token responde 401", %{conn: conn, course: course} do
    assert %{"errors" => _} = conn |> get(posts_path(course)) |> json_response(401)
  end

  test "la docente publica y lista", %{conn: conn, a: a, course: course, teacher: teacher} do
    conn = authed(conn, a, teacher)

    assert %{"data" => %{"id" => id, "body" => "Hola", "author" => %{"name" => name}}} =
             conn |> post(posts_path(course), %{body: "Hola"}) |> json_response(201)

    assert name == teacher.name
    assert %{"data" => [%{"id" => ^id}]} = conn |> get(posts_path(course)) |> json_response(200)
  end

  test "la estudiante no puede publicar", %{conn: conn, a: a, course: course, student: student} do
    conn = authed(conn, a, student)
    assert conn |> post(posts_path(course), %{body: "Hola"}) |> json_response(403)
  end

  test "cuerpo vacío responde 422", %{conn: conn, a: a, course: course, teacher: teacher} do
    assert %{"errors" => %{"body" => [_]}} =
             conn
             |> authed(a, teacher)
             |> post(posts_path(course), %{body: ""})
             |> json_response(422)
  end

  test "un token de otra institución no alcanza el curso", %{conn: conn, b: b, course: course} do
    admin_b = member_fixture(b, "institution_admin")
    assert conn |> authed(b, admin_b) |> get(posts_path(course)) |> json_response(404)
  end

  test "paridad: cada acción del catálogo es una operación de la API", %{conn: conn} do
    spec = conn |> get("/api/v1/openapi") |> json_response(200)

    operation_ids =
      for {_path, item} <- spec["paths"], {_verb, op} <- item, is_map(op), do: op["operationId"]

    for action <- Amauta.Actions.all() do
      assert action.name() in operation_ids, "falta #{action.name()} en la API"
    end
  end
end
