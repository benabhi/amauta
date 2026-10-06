defmodule Amauta.Platform do
  @moduledoc "Instancia y registro de instituciones."
  use Ash.Domain, otp_app: :amauta

  resources do
    resource Amauta.Platform.Institution do
      define :create_institution, action: :create
      define :get_institution_by_slug, action: :by_slug, args: [:slug], not_found_error?: false
    end
  end
end
