defmodule Amauta.Terminology do
  @moduledoc """
  Terminología configurable (ERS 4.9 y Anexo E).

  Cada institución elige un preset y puede ajustar cada término con su
  singular, su plural y su género gramatical, para que la interfaz concuerde
  («Nuevo curso» / «Nueva materia»). El código, la API y las URLs usan
  siempre los nombres canónicos en inglés; la terminología solo afecta lo
  que se muestra.

  El Anexo E no define cohorte ni período: todos los presets usan los
  términos genéricos, que la institución puede ajustar.

  Los presets están en español: la terminología es de la institución, no del
  idioma de la interfaz. Los idiomas adicionales (V1) traerán sus presets.
  """
  alias Amauta.Platform.Institution

  @type key :: :institution | :pathway | :course | :section | :unit | :stage | :cohort | :period
  @type gender :: :masculine | :feminine
  @type term_def :: %{singular: String.t(), plural: String.t(), gender: gender()}

  @keys [:institution, :pathway, :course, :section, :unit, :stage, :cohort, :period]

  @presets %{
    "generic" => %{
      institution: %{singular: "institución", plural: "instituciones", gender: :feminine},
      pathway: %{singular: "trayecto", plural: "trayectos", gender: :masculine},
      course: %{singular: "curso", plural: "cursos", gender: :masculine},
      section: %{singular: "comisión", plural: "comisiones", gender: :feminine},
      unit: %{singular: "unidad", plural: "unidades", gender: :feminine},
      stage: %{singular: "etapa", plural: "etapas", gender: :feminine},
      cohort: %{singular: "cohorte", plural: "cohortes", gender: :feminine},
      period: %{singular: "período", plural: "períodos", gender: :masculine}
    },
    "university" => %{
      institution: %{singular: "universidad", plural: "universidades", gender: :feminine},
      pathway: %{singular: "carrera", plural: "carreras", gender: :feminine},
      course: %{singular: "materia", plural: "materias", gender: :feminine},
      section: %{singular: "comisión", plural: "comisiones", gender: :feminine},
      unit: %{singular: "unidad", plural: "unidades", gender: :feminine},
      stage: %{singular: "año", plural: "años", gender: :masculine},
      cohort: %{singular: "cohorte", plural: "cohortes", gender: :feminine},
      period: %{singular: "período", plural: "períodos", gender: :masculine}
    },
    "tertiary" => %{
      institution: %{singular: "instituto", plural: "institutos", gender: :masculine},
      pathway: %{singular: "carrera", plural: "carreras", gender: :feminine},
      course: %{singular: "materia", plural: "materias", gender: :feminine},
      section: %{singular: "división", plural: "divisiones", gender: :feminine},
      unit: %{singular: "unidad", plural: "unidades", gender: :feminine},
      stage: %{singular: "año", plural: "años", gender: :masculine},
      cohort: %{singular: "cohorte", plural: "cohortes", gender: :feminine},
      period: %{singular: "período", plural: "períodos", gender: :masculine}
    },
    "postgraduate" => %{
      institution: %{
        singular: "escuela de posgrado",
        plural: "escuelas de posgrado",
        gender: :feminine
      },
      pathway: %{singular: "programa", plural: "programas", gender: :masculine},
      course: %{singular: "seminario", plural: "seminarios", gender: :masculine},
      section: %{singular: "grupo", plural: "grupos", gender: :masculine},
      unit: %{singular: "módulo", plural: "módulos", gender: :masculine},
      stage: %{singular: "ciclo", plural: "ciclos", gender: :masculine},
      cohort: %{singular: "cohorte", plural: "cohortes", gender: :feminine},
      period: %{singular: "período", plural: "períodos", gender: :masculine}
    }
  }

  @doc "Claves de los términos configurables."
  @spec keys() :: [key()]
  def keys, do: @keys

  @doc "Nombres de los presets."
  @spec presets() :: [String.t()]
  def presets, do: Map.keys(@presets)

  @doc "Definición de un término en la institución: preset más sus ajustes."
  @spec term(Institution.t() | %{institution: Institution.t()}, key()) :: term_def()
  def term(%{institution: %Institution{} = institution}, key), do: term(institution, key)

  def term(%Institution{terminology_preset: preset, terminology: overrides}, key)
      when key in @keys do
    base = @presets |> Map.get(preset, @presets["generic"]) |> Map.fetch!(key)

    case overrides && Map.get(overrides, Atom.to_string(key)) do
      %{"singular" => singular, "plural" => plural, "gender" => gender} ->
        %{singular: singular, plural: plural, gender: String.to_existing_atom(gender)}

      _ ->
        base
    end
  end

  @doc "Forma del término según la cantidad, en minúscula."
  @spec name(Institution.t() | %{institution: Institution.t()}, key(), pos_integer()) ::
          String.t()
  def name(tenant, key, count \\ 1) do
    term = term(tenant, key)
    if count == 1, do: term.singular, else: term.plural
  end

  @doc "Igual que `name/3`, con la primera letra en mayúscula."
  def title(tenant, key, count \\ 1) do
    tenant |> name(key, count) |> capitalize()
  end

  @doc "Género gramatical del término."
  @spec gender(Institution.t() | %{institution: Institution.t()}, key()) :: gender()
  def gender(tenant, key), do: term(tenant, key).gender

  @doc """
  Valida los ajustes de una institución: un mapa de clave a
  `%{"singular", "plural", "gender"}`.
  """
  @spec validate_overrides(map()) :: :ok | {:error, String.t()}
  def validate_overrides(overrides) when is_map(overrides) do
    allowed = Enum.map(@keys, &Atom.to_string/1)

    Enum.reduce_while(overrides, :ok, fn
      {key, %{"singular" => s, "plural" => p, "gender" => g}}, :ok
      when is_binary(s) and is_binary(p) and g in ["masculine", "feminine"] ->
        cond do
          key not in allowed -> {:halt, {:error, "unknown term: #{key}"}}
          String.trim(s) == "" or String.trim(p) == "" -> {:halt, {:error, "empty term: #{key}"}}
          true -> {:cont, :ok}
        end

      {key, _}, :ok ->
        {:halt, {:error, "invalid term: #{key}"}}
    end)
  end

  defp capitalize(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp capitalize(""), do: ""
end
