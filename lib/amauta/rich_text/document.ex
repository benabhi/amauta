defmodule Amauta.RichText.Document do
  @moduledoc """
  Tipo de Ecto para los campos de contenido enriquecido (columna `jsonb`).
  Acepta el documento como mapa o como el JSON que manda el formulario, y
  siempre lo guarda depurado (`Amauta.RichText.sanitize/1`). Un documento
  sin contenido se guarda como `nil`.

      field :description, Amauta.RichText.Document
  """
  use Ecto.Type

  alias Amauta.RichText

  @impl true
  def type, do: :map

  @impl true
  def cast(value) do
    case RichText.sanitize(value) do
      {:ok, doc} -> {:ok, if(RichText.blank?(doc), do: nil, else: doc)}
      {:error, :too_large} -> {:error, message: "is too long"}
      {:error, _} -> :error
    end
  end

  @impl true
  def load(value) when is_map(value), do: {:ok, value}
  def load(_value), do: :error

  @impl true
  def dump(nil), do: {:ok, nil}
  def dump(value) when is_map(value), do: {:ok, value}
  def dump(_value), do: :error
end
