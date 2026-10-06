if Code.ensure_loaded?(PhoenixStorybook) do
  defmodule AmautaWeb.Storybook do
    @moduledoc """
    Catálogo vivo de la biblioteca de componentes (ERS 6.5.7), solo en
    desarrollo: http://localhost:4000/storybook. Usa el mismo `app.css` de
    la aplicación, así que muestra exactamente los mismos tokens.
    """
    use PhoenixStorybook,
      otp_app: :amauta,
      content_path: Path.expand("../../storybook", __DIR__),
      css_path: "/assets/css/app.css",
      js_path: "/assets/js/storybook.js",
      sandbox_class: "amauta",
      title: "Amauta · Componentes",
      color_mode: true
  end
end
