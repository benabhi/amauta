defmodule Amauta.Periods.AcademicPeriod do
  @moduledoc """
  Período lectivo de la institución (RF-INS-009): un intervalo de fechas al
  que se asocian los cursos. A lo sumo uno es el actual. Anidarlos («2027»
  contiene «1.er cuatrimestre») llega en V1.
  """
  use Amauta.Schema

  @type t :: %__MODULE__{}

  schema "academic_periods" do
    field :name, :string
    field :starts_on, :date
    field :ends_on, :date
    field :current, :boolean, default: false

    timestamps()
  end

  def changeset(period, attrs) do
    period
    |> cast(attrs, [:name, :starts_on, :ends_on])
    |> update_change(:name, &trim/1)
    |> validate_required([:name, :starts_on, :ends_on])
    |> validate_length(:name, max: 120)
    |> validate_dates()
    |> unique_constraint(:name, name: :academic_periods_name_index, message: "already exists")
    |> check_constraint(:ends_on,
      name: :dates_must_be_ordered,
      message: "must be after the start"
    )
  end

  defp validate_dates(changeset) do
    starts_on = get_field(changeset, :starts_on)
    ends_on = get_field(changeset, :ends_on)

    if starts_on && ends_on && Date.before?(ends_on, starts_on) do
      add_error(changeset, :ends_on, "must be after the start")
    else
      changeset
    end
  end
end
