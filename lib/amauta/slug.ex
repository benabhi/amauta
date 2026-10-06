defmodule Amauta.Slug do
  @moduledoc """
  Slugs de trayectos y cursos (ERS 8.4): minúsculas, dígitos y guiones,
  sin tildes. «Lic. en Sistemas» → `lic-en-sistemas`.
  """

  @format ~r/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/

  @doc "Expresión que valida un slug."
  def format, do: @format

  @doc "Slug a partir de un texto libre."
  @spec slugify(String.t() | nil) :: String.t()
  def slugify(nil), do: ""

  def slugify(text) when is_binary(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 63)
    |> String.trim_trailing("-")
  end
end
