defmodule Amauta.Schema do
  @moduledoc """
  Base de los schemas de Ecto: claves UUIDv7 generadas por la aplicación y
  marcas de tiempo en UTC con microsegundos (ERS 8.12).
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset
      import Amauta.Schema, only: [trim: 1]

      @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
      @foreign_key_type Ecto.UUID
      @timestamps_opts [type: :utc_datetime_usec]
    end
  end

  @doc """
  Recorta los espacios de un texto y deja pasar `nil`. Para
  `update_change/3`: al vaciar un campo opcional, el cambio es `nil`.
  """
  @spec trim(String.t() | nil) :: String.t() | nil
  def trim(nil), do: nil
  def trim(text) when is_binary(text), do: String.trim(text)
end
