defmodule Amauta.Repo do
  use Ecto.Repo,
    otp_app: :amauta,
    adapter: Ecto.Adapters.Postgres
end
