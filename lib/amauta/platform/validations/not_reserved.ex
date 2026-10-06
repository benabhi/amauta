defmodule Amauta.Platform.Validations.NotReserved do
  @moduledoc "Rechaza los slugs reservados por las rutas (ERS 8.4)."
  use Ash.Resource.Validation

  @reserved ~w(api admin assets live health login dev)

  @impl true
  def validate(changeset, opts, _context) do
    attribute = opts[:attribute]

    if Ash.Changeset.get_attribute(changeset, attribute) in @reserved do
      {:error, field: attribute, message: "is reserved"}
    else
      :ok
    end
  end
end
