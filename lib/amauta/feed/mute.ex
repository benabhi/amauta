defmodule Amauta.Feed.Mute do
  @moduledoc """
  Persona silenciada en el tablón de un curso (RF-TAB-007): no puede
  publicar ni responder ahí, pero sigue leyendo y cursando.
  """
  use Amauta.Schema

  schema "feed_mutes" do
    field :muted_by_id, Ecto.UUID
    belongs_to :course, Amauta.Courses.Course
    belongs_to :user, Amauta.Accounts.User

    timestamps(updated_at: false)
  end
end
