defmodule Amauta.Scope do
  @moduledoc """
  Contexto de cada operación (patrón de *scopes* de Phoenix 1.8): la
  institución y la persona que actúa. Las funciones de dominio lo reciben
  como primer argumento y, por ser un «tenant», operan dentro del schema de
  su institución (`Amauta.Tenancy.opts/1`).

  Más adelante suma los permisos efectivos y los metadatos de la solicitud.
  """
  alias Amauta.Accounts.User
  alias Amauta.Platform.Institution

  @type t :: %__MODULE__{institution: Institution.t(), user: User.t() | nil}

  @enforce_keys [:institution]
  defstruct [:institution, :user]

  @doc "Scope de una institución sin persona (visitante)."
  def for_institution(%Institution{} = institution), do: %__MODULE__{institution: institution}

  @doc "Scope de una persona dentro de su institución."
  def for_user(%Institution{} = institution, %User{} = user),
    do: %__MODULE__{institution: institution, user: user}

  def for_user(%Institution{} = institution, nil), do: for_institution(institution)
end
