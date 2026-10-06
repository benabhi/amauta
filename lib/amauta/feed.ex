defmodule Amauta.Feed do
  @moduledoc "Tablón."
  use Ash.Domain, otp_app: :amauta, extensions: [AshJsonApi.Domain]

  json_api do
    routes do
      base_route "/courses/:course_id/posts", Amauta.Feed.Post do
        index :list
        post :create
      end
    end
  end

  resources do
    resource Amauta.Feed.Post do
      define :list_posts, action: :list, args: [:course_id]
      define :create_post, action: :create
    end
  end

  @doc "Tópico de PubSub del tablón de un curso (lo publica `Ash.Notifier.PubSub`)."
  def topic(%{schema_name: tenant}, course), do: "feed:#{tenant}:#{course.id}"

  def subscribe(institution, course) do
    Phoenix.PubSub.subscribe(Amauta.PubSub, topic(institution, course))
  end
end
