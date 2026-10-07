defmodule Amauta.Feed.Post do
  @moduledoc """
  Publicación del tablón (RF-TAB-001). Va a todo el curso o a una comisión
  (`section_id`). Mientras se escribe es un borrador (`draft`, uno por
  persona y curso); al publicarla pasa a `published`. Editarla deja la marca
  `edited_at` (RF-TAB-003).

  Fijada (RF-TAB-006): `pinned_at` con su orden (`pin_position`) y un
  vencimiento opcional (`pin_expires_at`). Vencida, deja de estar fijada
  (`Amauta.Feed.pinned?/2`).
  """
  use Amauta.Schema

  alias Amauta.Accounts.User
  alias Amauta.Courses.{Course, Section}

  @type t :: %__MODULE__{}

  schema "posts" do
    field :body, Amauta.RichText.Document
    field :status, :string, default: "draft"
    field :published_at, :utc_datetime_usec
    field :edited_at, :utc_datetime_usec
    field :replies_enabled, :boolean, default: true
    field :pinned_at, :utc_datetime_usec
    field :pin_position, :integer
    field :pin_expires_at, :utc_datetime_usec
    field :pinned_by_id, Ecto.UUID
    # Cuántas respuestas tiene en total y cuántas de primer nivel; las que
    # se muestran están en `replies` (ver `Amauta.Feed.with_replies/3`).
    field :reply_count, :integer, virtual: true, default: 0
    field :top_reply_count, :integer, virtual: true, default: 0

    belongs_to :course, Course
    belongs_to :author, User
    belongs_to :section, Section
    has_many :replies, Amauta.Feed.Reply
    has_many :attachments, Amauta.Feed.Attachment, preload_order: [asc: :position]

    timestamps()
  end

  @doc "Borrador: el cuerpo puede estar vacío."
  def draft_changeset(post, attrs) do
    post
    |> cast(attrs, [:body, :section_id])
    |> foreign_key_constraint(:section_id)
  end

  @doc "Publicar: hace falta contenido."
  def publish_changeset(post, attrs) do
    post
    |> cast(attrs, [:body, :section_id])
    |> validate_required([:body], message: "write something first")
    |> put_change(:status, "published")
    |> put_change(:published_at, DateTime.utc_now())
    |> foreign_key_constraint(:section_id)
  end

  @doc "Editar una publicación: deja la marca de editada."
  def edit_changeset(post, attrs) do
    post
    |> cast(attrs, [:body])
    |> validate_required([:body], message: "write something first")
    |> put_change(:edited_at, DateTime.utc_now())
  end
end
