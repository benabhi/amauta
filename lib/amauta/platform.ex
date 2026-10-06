defmodule Amauta.Platform do
  @moduledoc "Instancia y registro de instituciones."
  alias Amauta.Platform.Institution
  alias Amauta.Repo

  def get_institution_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Institution, slug: slug)
  end
end
