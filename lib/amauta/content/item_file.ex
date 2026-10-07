defmodule Amauta.Content.ItemFile do
  @moduledoc """
  Archivo de un material (RF-CON-002). El archivo
  (`Amauta.Files.StoredFile`, propósito `content_material`) se sube antes de
  guardar el elemento; este vínculo se crea al guardarlo.
  """
  use Amauta.Schema

  alias Amauta.Content.Item
  alias Amauta.Files.StoredFile

  @type t :: %__MODULE__{}

  schema "course_item_files" do
    field :position, :integer, default: 0

    belongs_to :item, Item
    belongs_to :file, StoredFile

    timestamps(updated_at: false)
  end
end
