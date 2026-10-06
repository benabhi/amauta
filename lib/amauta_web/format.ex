defmodule AmautaWeb.Format do
  @moduledoc """
  Fechas, horas, números y listas en el formato del idioma actual (CLDR,
  RF-I18N-002). Todo se guarda en UTC; para mostrarlo se convierte a la
  zona horaria que corresponda (RF-I18N-003).
  """
  alias Amauta.Cldr

  @doc "Fecha y hora en la zona dada. `format`: `:short`, `:medium` o `:long`."
  @spec datetime(DateTime.t(), String.t(), atom()) :: String.t()
  def datetime(%DateTime{} = datetime, timezone, format \\ :medium) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> Cldr.DateTime.to_string!(format: format)
  end

  @doc "Fecha (sin hora) en la zona dada."
  @spec date(DateTime.t(), String.t(), atom()) :: String.t()
  def date(%DateTime{} = datetime, timezone, format \\ :medium) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> DateTime.to_date()
    |> Cldr.Date.to_string!(format: format)
  end

  @doc "Día de calendario (`Date`, sin zona horaria), como las fechas de un período."
  @spec day(Date.t(), atom()) :: String.t()
  def day(%Date{} = date, format \\ :medium), do: Cldr.Date.to_string!(date, format: format)

  @doc "Número con los separadores del idioma."
  @spec number(number()) :: String.t()
  def number(number), do: Cldr.Number.to_string!(number)

  @doc "Lista con la conjunción del idioma («a, b y c»)."
  @spec list([String.t()]) :: String.t()
  def list(items), do: Cldr.List.to_string!(items)
end
