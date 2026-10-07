defmodule Amauta.Accounts.Directory do
  @moduledoc """
  Directorio de personas de una institución (RF-INS-004): búsqueda,
  filtros y paginación. Solo consulta; los cambios pasan por las acciones de
  `Amauta.Accounts.Actions`.
  """
  import Ecto.Query

  alias Amauta.Accounts.User
  alias Amauta.Authorization.RoleAssignment
  alias Amauta.{Repo, Tenancy}

  @per_page 50

  @type page :: %{
          entries: [User.t()],
          total: non_neg_integer(),
          page: pos_integer(),
          per_page: pos_integer()
        }

  @doc """
  Personas de la institución.

  Filtros: `:q` (nombre o email, sin distinguir mayúsculas),
  `:status` y `:role` (rol de sistema en cualquier ámbito).
  """
  @spec list(Tenancy.tenant(), map()) :: page()
  def list(tenant, filters \\ %{}) do
    page = max(to_int(filters[:page] || filters["page"]), 1)

    query =
      User
      |> filter_q(filters[:q] || filters["q"])
      |> filter_status(filters[:status] || filters["status"])
      |> filter_role(filters[:role] || filters["role"])

    opts = Tenancy.opts(tenant)

    %{
      entries:
        query
        |> order_by([u], [u.last_name, u.first_name, u.id])
        |> limit(@per_page)
        |> offset(^((page - 1) * @per_page))
        |> Repo.all(opts),
      total: Repo.aggregate(query, :count, opts),
      page: page,
      per_page: @per_page
    }
  end

  @doc "Todas las personas que cumplen los filtros, para exportar."
  def all(tenant, filters \\ %{}) do
    User
    |> filter_q(filters[:q] || filters["q"])
    |> filter_status(filters[:status] || filters["status"])
    |> filter_role(filters[:role] || filters["role"])
    |> order_by([u], [u.last_name, u.first_name, u.id])
    |> Repo.all(Tenancy.opts(tenant))
  end

  @doc "Roles de cada persona: `%{user_id => [rol]}`."
  def roles_by_user(tenant, users) do
    ids = Enum.map(users, & &1.id)

    from(a in RoleAssignment,
      where: a.user_id in ^ids,
      distinct: [a.user_id, a.role],
      select: {a.user_id, a.role}
    )
    |> Repo.all(Tenancy.opts(tenant))
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp filter_q(query, q) when is_binary(q) and q != "" do
    term = "%" <> (q |> String.trim() |> String.downcase() |> escape_like()) <> "%"

    where(
      query,
      [u],
      fragment(
        "lower(? || ' ' || ? || ' ' || ?) LIKE ?",
        u.first_name,
        u.last_name,
        u.email,
        ^term
      ) or
        fragment("lower(coalesce(?, '')) LIKE ?", u.preferred_name, ^term)
    )
  end

  defp filter_q(query, _), do: query

  defp filter_status(query, status) when status in ["invited", "active", "suspended", "archived"],
    do: where(query, [u], u.status == ^status)

  defp filter_status(query, _), do: query

  defp filter_role(query, role) when is_binary(role) and role != "" do
    where(
      query,
      [u],
      u.id in subquery(from(a in RoleAssignment, where: a.role == ^role, select: a.user_id))
    )
  end

  defp filter_role(query, _), do: query

  defp escape_like(term), do: String.replace(term, ~r/[\\%_]/, fn c -> "\\" <> c end)

  defp to_int(nil), do: 1
  defp to_int(n) when is_integer(n), do: n

  defp to_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> 1
    end
  end
end
