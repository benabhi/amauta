defmodule Amauta.Audit do
  @moduledoc "Auditoría por institución."
  use Ash.Domain, otp_app: :amauta

  resources do
    resource Amauta.Audit.Event
  end

  def list_events(tenant) do
    Amauta.Audit.Event
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(tenant: tenant, authorize?: false)
  end
end
