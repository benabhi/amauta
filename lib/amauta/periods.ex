defmodule Amauta.Periods do
  @moduledoc """
  Períodos lectivos de la institución (RF-INS-009). Solo consultas y
  operaciones sin permisos: los cambios desde la interfaz pasan por
  `Amauta.Periods.Actions`.
  """
  import Ecto.Query

  alias Amauta.Periods.AcademicPeriod
  alias Amauta.{Repo, Tenancy}

  @doc "Períodos, del más reciente al más antiguo."
  @spec list(Tenancy.tenant()) :: [AcademicPeriod.t()]
  def list(tenant) do
    AcademicPeriod
    |> order_by([p], desc: p.starts_on, asc: p.name)
    |> Repo.all(Tenancy.opts(tenant))
  end

  @doc "El período actual, o `nil`."
  @spec current(Tenancy.tenant()) :: AcademicPeriod.t() | nil
  def current(tenant), do: Repo.get_by(AcademicPeriod, [current: true], Tenancy.opts(tenant))

  @doc "Período por ID, o `nil`."
  def get(tenant, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(AcademicPeriod, id, Tenancy.opts(tenant))
      :error -> nil
    end
  end

  @doc "Crea un período. No verifica permisos."
  def create(tenant, attrs) do
    %AcademicPeriod{}
    |> AcademicPeriod.changeset(attrs)
    |> Repo.insert(Tenancy.opts(tenant))
  end

  @doc """
  Marca el período como actual y desmarca el anterior. Debe correr dentro
  de una transacción (las acciones ya lo hacen).
  """
  def set_current(tenant, %AcademicPeriod{} = period) do
    opts = Tenancy.opts(tenant)

    from(p in AcademicPeriod, where: p.current and p.id != ^period.id)
    |> Repo.update_all([set: [current: false]], opts)

    period
    |> Ecto.Changeset.change(current: true)
    |> Repo.update(opts)
  end
end
