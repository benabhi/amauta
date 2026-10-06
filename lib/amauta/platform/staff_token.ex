defmodule Amauta.Platform.StaffToken do
  @moduledoc "Token de sesión del personal de plataforma."
  use Amauta.Schema
  import Ecto.Query

  @session_validity_in_days 7

  @schema_prefix "global"
  schema "platform_staff_tokens" do
    field :token, :binary
    field :context, :string
    belongs_to :staff, Amauta.Platform.Staff

    timestamps(updated_at: false)
  end

  def build_session_token(staff) do
    token = :crypto.strong_rand_bytes(32)
    {token, %__MODULE__{token: token, context: "session", staff_id: staff.id}}
  end

  @doc "Personal del token de sesión, si el token es válido."
  def verify_session_token_query(token) do
    from t in __MODULE__,
      join: s in assoc(t, :staff),
      where: t.token == ^token and t.context == "session",
      where: t.inserted_at > ago(@session_validity_in_days, "day"),
      select: s
  end
end
