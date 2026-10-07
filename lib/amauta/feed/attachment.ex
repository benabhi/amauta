defmodule Amauta.Feed.Attachment do
  @moduledoc """
  Archivo adjunto a una publicación o a una respuesta del tablón
  (RF-TAB-005). El archivo (`Amauta.Files.StoredFile`, propósito
  `feed_attachment`) se sube antes de publicar; este vínculo se crea al
  guardar el borrador, publicar o responder.
  """
  use Amauta.Schema

  alias Amauta.Feed.{Post, Reply}
  alias Amauta.Files.StoredFile

  @type t :: %__MODULE__{}

  schema "feed_attachments" do
    field :position, :integer, default: 0

    belongs_to :post, Post
    belongs_to :reply, Reply
    belongs_to :file, StoredFile

    timestamps(updated_at: false)
  end
end
