defmodule AmautaWeb.StorybookRoutes do
  @moduledoc """
  Rutas del catálogo vivo de componentes. PhoenixStorybook solo existe en
  desarrollo: la macro agrega las rutas si la dependencia está cargada y,
  si no, no agrega nada (así el router compila en test y en producción).
  """

  defmacro routes do
    if Code.ensure_loaded?(PhoenixStorybook.Router) do
      quote do
        require PhoenixStorybook.Router

        scope "/" do
          PhoenixStorybook.Router.storybook_assets()
        end

        scope "/" do
          pipe_through :browser

          PhoenixStorybook.Router.live_storybook("/storybook",
            backend_module: AmautaWeb.Storybook
          )
        end
      end
    end
  end
end
