defmodule AmautaWeb.TestGettext do
  @moduledoc """
  Backend de Gettext para probar `AmautaWeb.Terminology.gettext_term/4`
  con mensajes que todavía no usa la interfaz.
  """
  use Gettext.Backend, otp_app: :amauta, priv: "test/support/gettext", default_locale: "es"
end

defmodule AmautaWeb.TestTerminologyMessages do
  @moduledoc false
  use Gettext, backend: AmautaWeb.TestGettext
  import AmautaWeb.Terminology

  def new_item(tenant, key), do: gettext_term(tenant, key, "New %{term}")
  def all_items(tenant, key), do: gettext_term(tenant, key, "All the %{terms}")
end
