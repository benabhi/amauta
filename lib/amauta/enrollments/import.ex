defmodule Amauta.Enrollments.Import do
  @moduledoc """
  Matriculación desde CSV (RF-MAT-001): una persona por fila, identificada
  por su email, con un rol y una comisión opcionales. Las personas tienen
  que existir en la institución (se importan antes, desde Personas).

  Lee el archivo con `Amauta.Accounts.Import.parse/1` (coma o punto y coma,
  UTF-8 con o sin BOM) y arma un plan por fila, sin cambiar nada. Aplicarlo
  es la acción `Amauta.Enrollments.Actions.ImportEnrollments`.
  """
  alias Amauta.Accounts.Import, as: CSV
  alias Amauta.Courses.Course
  alias Amauta.Enrollments

  # Encabezados reconocidos, ya normalizados (minúsculas, sin tildes).
  @columns %{
    email: ~w(email e-mail mail correo correo_electronico),
    role: ~w(role rol),
    section: ~w(section comision seccion division grupo)
  }

  # Valores de rol reconocidos.
  @roles %{
    "student" => ~w(student estudiante alumno alumna),
    "teacher" => ~w(teacher docente profesor profesora),
    "assistant" => ~w(assistant ayudante auxiliar),
    "course_lead" => ~w(course_lead responsable titular),
    "observer" => ~w(observer observador observadora)
  }

  @type row :: %{
          line: pos_integer(),
          email: String.t(),
          user_id: Ecto.UUID.t() | nil,
          role: String.t() | nil,
          section_id: Ecto.UUID.t() | nil,
          status: :enroll | :already | :error,
          errors: [atom()]
        }

  defdelegate parse(content), to: CSV

  @doc """
  Plan de matriculación: una entrada por fila. Sin columna de email, `{:error, :no_email}`.
  """
  @spec plan(Amauta.Tenancy.tenant(), Course.t(), %{headers: list(), rows: list()}) ::
          {:ok, [row()]} | {:error, :no_email}
  def plan(tenant, %Course{} = course, %{headers: headers, rows: rows}) do
    index = column_index(headers)

    if is_nil(index.email) do
      {:error, :no_email}
    else
      sections =
        tenant
        |> Enrollments.list_sections(course)
        |> Map.new(&{normalize(&1.name), &1.id})

      emails = Enum.map(rows, &cell(&1, index.email))
      users = Enrollments.users_by_email(tenant, Enum.reject(emails, &(&1 == "")))

      active =
        tenant
        |> Enrollments.list(course, %{"status" => "active"})
        |> MapSet.new(& &1.user_id)

      {plan, _seen} =
        rows
        |> Enum.with_index(2)
        |> Enum.map_reduce(MapSet.new(), fn {row, line}, seen ->
          email = String.downcase(cell(row, index.email))
          entry = build(line, email, row, index, users, sections, active, seen)
          {entry, MapSet.put(seen, email)}
        end)

      {:ok, plan}
    end
  end

  defp build(line, email, row, index, users, sections, active, seen) do
    user = users[email]
    {role, role_error} = role(cell(row, index.role))
    {section_id, section_error} = section(cell(row, index.section), sections)

    errors =
      [
        email == "" && :missing_email,
        email != "" && is_nil(user) && :unknown_user,
        MapSet.member?(seen, email) && email != "" && :repeated,
        role_error,
        section_error
      ]
      |> Enum.reject(&(&1 in [nil, false]))

    status =
      cond do
        errors != [] -> :error
        MapSet.member?(active, user.id) -> :already
        true -> :enroll
      end

    %{
      line: line,
      email: email,
      user_id: user && user.id,
      role: role,
      section_id: section_id,
      status: status,
      errors: errors
    }
  end

  @doc "Filas listas para la acción de importar."
  def rows_to_apply(plan) do
    for %{status: :enroll} = row <- plan,
        do: %{"user_id" => row.user_id, "role" => row.role, "section_id" => row.section_id}
  end

  @doc "Cantidades por estado."
  def summary(plan) do
    counts = Enum.frequencies_by(plan, & &1.status)
    %{enroll: counts[:enroll] || 0, already: counts[:already] || 0, error: counts[:error] || 0}
  end

  defp role(""), do: {"student", nil}

  defp role(value) do
    normalized = normalize(value)

    case Enum.find(@roles, fn {_key, names} -> normalized in names end) do
      {key, _} -> {key, nil}
      nil -> {nil, :unknown_role}
    end
  end

  defp section("", _sections), do: {nil, nil}

  defp section(value, sections) do
    case sections[normalize(value)] do
      nil -> {nil, :unknown_section}
      id -> {id, nil}
    end
  end

  defp column_index(headers) do
    normalized = headers |> Enum.map(&normalize/1) |> Enum.with_index()

    Map.new(@columns, fn {column, names} ->
      {column, Enum.find_value(normalized, fn {h, i} -> if h in names, do: i end)}
    end)
  end

  defp cell(_row, nil), do: ""
  defp cell(row, index), do: row |> Enum.at(index, "") |> String.trim()

  defp normalize(text) do
    text
    |> String.trim()
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/\s+/, "_")
  end
end
