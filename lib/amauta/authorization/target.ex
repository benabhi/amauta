defprotocol Amauta.Authorization.Target do
  @moduledoc """
  Sobre qué se pide un permiso. Cada entidad con ámbito (trayecto, curso,
  comisión) implementa este protocolo y devuelve la cadena de ámbitos que la
  contienen, para resolver la cascada (RF-ROL-003).
  """

  @doc """
  Ámbitos que contienen al objetivo, del más específico al más general, sin
  la institución (que siempre aplica). Por ejemplo, una comisión:
  `[{"section", id}, {"course", id}, {"pathway", id}]`.
  """
  @spec scope_chain(t()) :: [{String.t(), Ecto.UUID.t()}]
  def scope_chain(target)
end

defimpl Amauta.Authorization.Target, for: Amauta.Platform.Institution do
  def scope_chain(_institution), do: []
end

defmodule Amauta.Authorization.ScopeRef do
  @moduledoc """
  Referencia a un ámbito por tipo e ID, con los ámbitos que lo contienen.
  Sirve cuando no hace falta (o todavía no existe) la entidad completa: en
  H0 los trayectos, cursos y comisiones aún no tienen tabla.
  """
  @enforce_keys [:type, :id]
  defstruct [:type, :id, parents: []]

  @type t :: %__MODULE__{
          type: String.t(),
          id: Ecto.UUID.t(),
          parents: [{String.t(), Ecto.UUID.t()}]
        }

  defimpl Amauta.Authorization.Target do
    def scope_chain(%{type: type, id: id, parents: parents}), do: [{type, id} | parents]
  end
end
