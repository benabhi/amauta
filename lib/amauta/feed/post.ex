defmodule Amauta.Feed.Post do
  @moduledoc "Publicación del tablón de un curso."
  use Amauta.Schema

  schema "posts" do
    field :body, :string
    belongs_to :course, Amauta.Catalog.Course
    belongs_to :author, Amauta.Accounts.User

    timestamps()
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body])
    |> validate_length(:body, max: 10_000)
  end
end
