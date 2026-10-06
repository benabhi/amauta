defmodule AmautaWeb.ErrorMessages do
  @moduledoc """
  Mensajes de validación propios de Amauta. Se traducen en tiempo de
  ejecución (`AmautaWeb.CoreComponents.translate_error/1`), así que se
  declaran acá para que `mix gettext.extract` los incluya en `errors.pot`.
  """
  use Gettext, backend: AmautaWeb.Gettext

  @doc false
  def messages do
    [
      dgettext_noop("errors", "did not change"),
      dgettext_noop("errors", "already assigned"),
      dgettext_noop("errors", "does not match password"),
      dgettext_noop("errors", "must have the @ sign and no spaces")
    ]
  end
end
