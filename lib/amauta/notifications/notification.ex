defmodule Amauta.Notifications.Notification do
  @moduledoc """
  Una notificación para una persona (RF-NOT-001 y 002): qué pasó (`event`,
  con sus datos en `data`), dónde (`course`), quién (`actor`), adónde ir
  (`url`) y por qué la recibe (`reason`).

  Las no leídas del mismo grupo (`group_key`, por ejemplo las respuestas a
  una misma publicación) se suman en una sola (`count`).
  """
  use Amauta.Schema

  @type t :: %__MODULE__{}

  schema "notifications" do
    field :event, :string
    field :data, :map, default: %{}
    field :url, :string
    field :reason, :string
    field :group_key, :string
    field :count, :integer, default: 1
    field :read_at, :utc_datetime_usec
    field :email_pending, :boolean, default: false
    field :emailed_at, :utc_datetime_usec

    belongs_to :user, Amauta.Accounts.User
    belongs_to :course, Amauta.Courses.Course
    belongs_to :actor, Amauta.Accounts.User

    timestamps()
  end
end
