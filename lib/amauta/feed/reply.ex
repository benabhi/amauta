defmodule Amauta.Feed.Reply do
  @moduledoc """
  Respuesta a una publicación del tablón (RF-TAB-004). Puede responder a
  otra respuesta, con un solo nivel de anidación: `parent_id` es siempre una
  respuesta de primer nivel, para que la conversación siga siendo legible.
  Ocultarla (moderación, RF-TAB-007) no la borra.
  """
  use Amauta.Schema

  alias Amauta.Accounts.User
  alias Amauta.Feed.Post

  @type t :: %__MODULE__{}

  schema "post_replies" do
    field :body, Amauta.RichText.Document
    field :edited_at, :utc_datetime_usec
    field :hidden_at, :utc_datetime_usec
    field :hidden_by_id, Ecto.UUID
    # Cuántas anidadas tiene; las que se muestran están en `children`.
    field :child_count, :integer, virtual: true, default: 0

    belongs_to :post, Post
    belongs_to :parent, __MODULE__
    belongs_to :author, User
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :attachments, Amauta.Feed.Attachment, preload_order: [asc: :position]

    timestamps()
  end

  def create_changeset(reply, attrs) do
    reply
    |> cast(attrs, [:body])
    |> validate_required([:body], message: "write something first")
  end

  def edit_changeset(reply, attrs) do
    reply
    |> cast(attrs, [:body])
    |> validate_required([:body], message: "write something first")
    |> put_change(:edited_at, DateTime.utc_now())
  end
end
