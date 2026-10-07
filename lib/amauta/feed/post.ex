defmodule Amauta.Feed.Post do
  @moduledoc """
  Publicación del tablón (RF-TAB-001). Va a todo el curso o a una comisión
  (`section_id`). Mientras se escribe es un borrador (`draft`, uno por
  persona y curso); al publicarla pasa a `published`. Editarla deja la marca
  `edited_at` (RF-TAB-003).
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

    belongs_to :course, Course
    belongs_to :author, User
    belongs_to :section, Section
    has_many :replies, Amauta.Feed.Reply

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
