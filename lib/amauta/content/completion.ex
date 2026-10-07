defmodule Amauta.Content.Completion do
  @moduledoc """
  Un elemento que una persona marcó como hecho (RF-CON-006). Hay uno por
  persona y elemento; desmarcarlo lo borra.
  """
  use Amauta.Schema

  @type t :: %__MODULE__{}

  schema "course_item_completions" do
    field :completed_at, :utc_datetime_usec

    belongs_to :item, Amauta.Content.Item
    belongs_to :user, Amauta.Accounts.User
    belongs_to :course, Amauta.Courses.Course
  end
end
