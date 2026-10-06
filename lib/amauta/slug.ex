defmodule Amauta.Slug do
  @moduledoc """
  Slugs de trayectos y cursos (ERS 8.4): minúsculas, dígitos y guiones,
  sin tildes. «Lic. en Sistemas» → `lic-en-sistemas`.
  """

  import Ecto.Query

  alias Amauta.{Repo, Tenancy}

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

  @doc """
  Primer slug libre en la tabla del schema: `base`, `base-2`, `base-3`…
  Con una base vacía devuelve `nil` (el changeset lo marca como obligatorio).
  """
  @spec available(Tenancy.tenant(), module(), String.t()) :: String.t() | nil
  def available(_tenant, _schema, ""), do: nil

  def available(tenant, schema, base) do
    taken =
      from(r in schema, where: r.slug == ^base or like(r.slug, ^"#{base}-%"), select: r.slug)
      |> Repo.all(Tenancy.opts(tenant))
      |> MapSet.new()

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}-#{n}"
    end)
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end
end
