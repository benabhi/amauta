defmodule Amauta.Storage.Local do
  @moduledoc """
  Adaptador en disco de `Amauta.Storage`, solo para desarrollo y pruebas.
  Las URLs «prefirmadas» son simbólicas (`local://…`): no hay servidor que
  las atienda.
  """
  @behaviour Amauta.Storage

  @impl true
  def presign_upload(key, opts) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")
    {:ok, %{url: url(key, "PUT", opts), headers: %{"content-type" => content_type}}}
  end

  @impl true
  def presign_download(key, opts), do: {:ok, url(key, "GET", opts)}

  @impl true
  def head(key) do
    case File.stat(path(key)) do
      {:ok, %{size: size}} -> {:ok, %{size: size, content_type: read_type(key)}}
      {:error, _} -> {:error, :not_found}
    end
  end

  @impl true
  def put(key, content, opts) do
    path = path(key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    File.write!(path <> ".type", Keyword.get(opts, :content_type, "application/octet-stream"))
    :ok
  end

  @impl true
  def get(key) do
    case File.read(path(key)) do
      {:ok, content} -> {:ok, content}
      {:error, _} -> {:error, :not_found}
    end
  end

  @impl true
  def delete(key) do
    File.rm(path(key))
    File.rm(path(key) <> ".type")
    :ok
  end

  defp url(key, method, opts) do
    expires = System.os_time(:second) + Keyword.fetch!(opts, :expires_in)
    "local://#{bucket()}/#{key}?method=#{method}&expires=#{expires}"
  end

  defp read_type(key) do
    case File.read(path(key) <> ".type") do
      {:ok, type} -> type
      {:error, _} -> nil
    end
  end

  defp path(key) do
    # La clave nunca puede salir de la raíz.
    true = not String.contains?(key, "..")
    Path.join([root(), bucket(), key])
  end

  defp root, do: Keyword.fetch!(Amauta.Storage.config(), :root)
  defp bucket, do: Keyword.fetch!(Amauta.Storage.config(), :bucket)
end
