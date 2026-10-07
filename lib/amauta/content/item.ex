defmodule Amauta.Content.Item do
  @moduledoc """
  Elemento de una unidad (RF-CON-002). En el MVP:

    * `page`: contenido armado con el editor de bloques (`body`).
    * `material`: archivos (`files`) y un enlace opcional (`url`), con una
      descripción en `body`.

  Se ordena dentro de su unidad (`position`) y se puede mover a otra
  (RF-CON-004). La visibilidad es como la de las unidades
  (`Amauta.Content.Unit`): un elemento visible dentro de una unidad oculta
  tampoco se ve.
  """
  use Amauta.Schema

  alias Amauta.Accounts.User
  alias Amauta.Content.{ItemFile, Unit}
  alias Amauta.Courses.Course

  @type t :: %__MODULE__{}

  @kinds ~w(page material)

  schema "course_items" do
    field :kind, :string
    field :title, :string
    field :body, Amauta.RichText.Document
    field :url, :string
    field :visibility, :string, default: "visible"
    field :publish_at, :utc_datetime_usec
    field :position, :integer, default: 0
    # Avisar en el tablón cuando el estudiantado empiece a verlo; cuándo se avisó.
    field :announce, :boolean, default: false
    field :announced_at, :utc_datetime_usec

    belongs_to :course, Course
    belongs_to :unit, Unit
    belongs_to :created_by, User
    has_many :files, ItemFile, preload_order: [asc: :position]

    timestamps()
  end

  @doc "Tipos de elemento del MVP."
  def kinds, do: @kinds

  def create_changeset(item, attrs) do
    item
    |> cast(attrs, [:kind])
    |> validate_required([:kind])
    |> validate_inclusion(:kind, @kinds)
    |> changeset(attrs)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:title, :body, :url, :visibility, :publish_at, :announce])
    |> update_change(:title, &trim/1)
    |> update_change(:url, &trim/1)
    |> validate_required([:title])
    |> validate_length(:title, max: 160)
    |> validate_url()
    |> Amauta.Content.validate_visibility()
  end

  # Solo enlaces web: nada de javascript: ni rutas sueltas.
  defp validate_url(changeset) do
    validate_change(changeset, :url, fn :url, url ->
      case URI.parse(url) do
        %URI{scheme: scheme, host: host}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _ ->
          [url: "must be a web address (https://…)"]
      end
    end)
  end
end
