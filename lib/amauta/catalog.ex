defmodule Amauta.Catalog do
  @moduledoc "Cursos."
  use Ash.Domain, otp_app: :amauta

  resources do
    resource Amauta.Catalog.Course do
      define :create_course, action: :create
      define :get_course, action: :read, get_by: [:id], not_found_error?: false
      define :get_course_by_slug, action: :by_slug, args: [:slug], not_found_error?: false
    end
  end
end
