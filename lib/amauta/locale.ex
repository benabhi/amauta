defmodule Amauta.Locale do
  @moduledoc """
  Idiomas de la interfaz (sección 5.30 del ERS).

  El idioma base es el español rioplatense (`"es"`, con voseo). El idioma
  de cada solicitud se resuelve en este orden: preferencia de la persona,
  institución, instancia (RF-I18N-004).

  Cada idioma de Gettext tiene su equivalente en CLDR para los formatos de
  fechas y números.
  """
  alias Amauta.Accounts.User
  alias Amauta.Platform.Institution

  @default "es"
  @supported %{"es" => "es-AR", "en" => "en"}

  @doc "Idiomas soportados."
  @spec supported() :: [String.t()]
  def supported, do: Map.keys(@supported)

  @doc "Idioma por defecto de la instancia."
  @spec default() :: String.t()
  def default, do: @default

  @spec supported?(term()) :: boolean()
  def supported?(locale), do: Map.has_key?(@supported, locale)

  @doc "Resuelve el idioma: persona, institución, instancia."
  @spec resolve(User.t() | nil, Institution.t() | nil) :: String.t()
  def resolve(user, institution) do
    Enum.find(
      [user && user.locale, institution && institution.locale],
      @default,
      &supported?/1
    )
  end

  @doc "Fija el idioma del proceso para Gettext y CLDR."
  @spec put(String.t()) :: :ok
  def put(locale) do
    locale = if supported?(locale), do: locale, else: @default
    Gettext.put_locale(AmautaWeb.Gettext, locale)
    {:ok, _} = Amauta.Cldr.put_locale(Map.fetch!(@supported, locale))
    :ok
  end

  @doc "Idioma de CLDR de un idioma de la interfaz."
  @spec cldr(String.t()) :: String.t()
  def cldr(locale), do: Map.get(@supported, locale, Map.fetch!(@supported, @default))
end
