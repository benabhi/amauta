defmodule AmautaWeb.Api.Schemas do
  @moduledoc "Schemas OpenAPI de la API."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  defmodule Post do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "Post",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        body: %Schema{type: :string},
        author: %Schema{
          type: :object,
          properties: %{id: %Schema{type: :string, format: :uuid}, name: %Schema{type: :string}}
        },
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :body, :author, :inserted_at]
    })
  end

  defmodule PostResponse do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "PostResponse",
      type: :object,
      properties: %{data: Post},
      required: [:data]
    })
  end

  defmodule PostListResponse do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "PostListResponse",
      type: :object,
      properties: %{data: %Schema{type: :array, items: Post}},
      required: [:data]
    })
  end

  defmodule PostParams do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "PostParams",
      type: :object,
      properties: %{body: %Schema{type: :string, maxLength: 10_000}},
      required: [:body]
    })
  end

  defmodule Error do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "Error",
      type: :object,
      properties: %{errors: %Schema{type: :object}}
    })
  end
end
