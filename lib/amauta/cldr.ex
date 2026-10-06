defmodule Amauta.Cldr do
  @moduledoc """
  Formatos locales de fechas, horas, números y listas según CLDR
  (RF-I18N-002). Los datos de cada idioma se descargan al compilar; en
  tiempo de ejecución no se consulta la red (P4).
  """
  use Cldr,
    locales: ["es-AR", "es", "en"],
    default_locale: "es-AR",
    providers: [Cldr.Number, Cldr.Calendar, Cldr.DateTime, Cldr.List]
end
