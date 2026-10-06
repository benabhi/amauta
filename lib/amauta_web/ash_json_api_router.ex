defmodule AmautaWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [Amauta.Feed],
    open_api: "/open_api"
end
