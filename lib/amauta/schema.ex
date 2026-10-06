defmodule Amauta.Schema do
  @moduledoc """
  Base de los schemas de Ecto: claves UUIDv7 generadas por la aplicación y
  marcas de tiempo en UTC con microsegundos (ERS 8.12).
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset

      @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
      @foreign_key_type Ecto.UUID
      @timestamps_opts [type: :utc_datetime_usec]
    end
  end
end
