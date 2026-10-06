defmodule Amauta.Accounts.User do
  @moduledoc "Persona de una institución."
  use Amauta.Schema

  schema "users" do
    field :name, :string
    field :email, :string
    field :api_token_hash, :binary, redact: true

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email])
    |> validate_required([:name, :email])
    |> validate_format(:email, ~r/^[^@\s]+@[^@\s]+$/)
    |> unique_constraint(:email)
  end
end
