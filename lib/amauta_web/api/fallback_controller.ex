defmodule AmautaWeb.Api.FallbackController do
  @moduledoc "Traduce los errores de las acciones a respuestas HTTP."
  use AmautaWeb, :controller

  def call(conn, {:error, :not_found}), do: error(conn, :not_found, "Not Found")
  def call(conn, {:error, :forbidden}), do: error(conn, :forbidden, "Forbidden")

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    errors = Ecto.Changeset.traverse_errors(changeset, &translate/1)
    conn |> put_status(:unprocessable_entity) |> json(%{errors: errors})
  end

  defp error(conn, status, detail) do
    conn |> put_status(status) |> json(%{errors: %{detail: detail}})
  end

  defp translate({message, opts}) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
