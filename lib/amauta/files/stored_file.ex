defmodule Amauta.Files.StoredFile do
  @moduledoc """
  Un archivo subido al almacenamiento (RF-ARC-001). La aplicación nunca
  recibe el contenido: guarda la clave, el nombre, el tamaño y el tipo real
  verificado. Estados: `pending` (pedida la subida), `ready` (verificado) y
  `rejected` (no pasó la verificación; el objeto se borró).
  """
  use Amauta.Schema

  @type t :: %__MODULE__{}

  @statuses ~w(pending ready rejected)

  schema "files" do
    field :purpose, :string
    field :owner_id, Ecto.UUID
    field :key, :string
    field :filename, :string
    field :declared_type, :string
    field :content_type, :string
    field :size, :integer
    field :status, :string, default: "pending"
    field :rejection_reason, :string
    field :upload_id, :string
    field :uploaded_by_id, Ecto.UUID

    timestamps()
  end

  def statuses, do: @statuses

  def create_changeset(file, attrs) do
    file
    |> cast(attrs, [
      :purpose,
      :owner_id,
      :key,
      :filename,
      :declared_type,
      :size,
      :upload_id,
      :uploaded_by_id
    ])
    |> validate_required([:purpose, :key, :filename, :size])
    |> validate_number(:size, greater_than: 0)
    |> validate_length(:filename, max: 255)
    |> unique_constraint(:key)
  end
end
