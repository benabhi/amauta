defmodule AmautaWeb.ApiSpec do
  @moduledoc "Especificación OpenAPI generada desde el router y los controladores."
  alias OpenApiSpex.{Components, Info, OpenApi, Paths, SecurityScheme}
  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      info: %Info{title: "Amauta API", version: "1"},
      paths: Paths.from_router(AmautaWeb.Router),
      components: %Components{
        securitySchemes: %{"bearer" => %SecurityScheme{type: "http", scheme: "bearer"}}
      },
      security: [%{"bearer" => []}]
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
