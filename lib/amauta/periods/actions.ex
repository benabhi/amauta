defmodule Amauta.Periods.Actions.CreatePeriod do
  @moduledoc "Crea un período lectivo y, si se pide, lo marca como actual (RF-INS-009)."
  use Amauta.Action,
    name: "periods.period.create",
    description: "Crea un período lectivo.",
    params: [
      name: {:string, required: true},
      starts_on: {:date, required: true},
      ends_on: {:date, required: true},
      current: :boolean
    ]

  alias Amauta.{Authorization, Periods}

  @impl true
  def authorize(scope, _input), do: Authorization.authorize(scope, "institution.periods.manage")

  @impl true
  def run(scope, input) do
    with {:ok, period} <- Periods.create(scope, input) do
      if input[:current], do: Periods.set_current(scope, period), else: {:ok, period}
    end
  end
end

defmodule Amauta.Periods.Actions.UpdatePeriod do
  @moduledoc "Edita el nombre y las fechas de un período lectivo."
  use Amauta.Action,
    name: "periods.period.update",
    description: "Edita un período lectivo.",
    params: [
      period_id: {Ecto.UUID, required: true},
      name: :string,
      starts_on: :date,
      ends_on: :date
    ]

  alias Amauta.Periods.AcademicPeriod
  alias Amauta.{Authorization, Periods, Repo, Tenancy}

  @impl true
  def authorize(scope, _input), do: Authorization.authorize(scope, "institution.periods.manage")

  @impl true
  def run(scope, %{period_id: id} = input) do
    case Periods.get(scope, id) do
      nil ->
        {:error, :not_found}

      period ->
        period
        |> AcademicPeriod.changeset(Map.delete(input, :period_id))
        |> Repo.update(Tenancy.opts(scope))
    end
  end
end

defmodule Amauta.Periods.Actions.SetCurrentPeriod do
  @moduledoc "Marca un período como el actual; el que lo era deja de serlo."
  use Amauta.Action,
    name: "periods.period.set_current",
    description: "Marca el período lectivo actual.",
    params: [period_id: {Ecto.UUID, required: true}]

  alias Amauta.{Authorization, Periods}

  @impl true
  def authorize(scope, _input), do: Authorization.authorize(scope, "institution.periods.manage")

  @impl true
  def run(scope, %{period_id: id}) do
    case Periods.get(scope, id) do
      nil -> {:error, :not_found}
      period -> Periods.set_current(scope, period)
    end
  end
end
