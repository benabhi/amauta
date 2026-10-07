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

  # Las partes se guardan en una carpeta junto al objeto y se concatenan al
  # completar, como hace S3.

  @impl true
  def start_multipart(key, opts) do
    upload_id = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    dir = parts_dir(key, upload_id)
    File.mkdir_p!(dir)

    File.write!(
      Path.join(dir, "type"),
      Keyword.get(opts, :content_type, "application/octet-stream")
    )

    {:ok, upload_id}
  end

  @impl true
  def presign_part(key, upload_id, part_number, opts),
    do: {:ok, url(key, "PUT", opts) <> "&uploadId=#{upload_id}&partNumber=#{part_number}"}

  @doc "Solo para pruebas: guarda una parte, como lo haría el navegador."
  def put_part(key, upload_id, part_number, content) do
    File.write!(Path.join(parts_dir(key, upload_id), "part-#{part_number}"), content)
    :ok
  end

  @impl true
  def list_parts(key, upload_id) do
    dir = parts_dir(key, upload_id)

    case File.ls(dir) do
      {:ok, files} ->
        parts =
          for "part-" <> number <- files do
            path = Path.join(dir, "part-" <> number)

            %{
              part_number: String.to_integer(number),
              etag: etag(path),
              size: File.stat!(path).size
            }
          end

        {:ok, Enum.sort_by(parts, & &1.part_number)}

      {:error, _} ->
        {:error, :not_found}
    end
  end

  @impl true
  def complete_multipart(key, upload_id, parts) do
    dir = parts_dir(key, upload_id)

    content =
      for {number, _etag} <- Enum.sort_by(parts, &elem(&1, 0)),
          do: File.read!(Path.join(dir, "part-#{number}"))

    :ok = put(key, content, content_type: File.read!(Path.join(dir, "type")))
    File.rm_rf!(dir)
    :ok
  end

  @impl true
  def abort_multipart(key, upload_id) do
    File.rm_rf!(parts_dir(key, upload_id))
    :ok
  end

  @impl true
  def get_head_bytes(key, length) do
    case File.open(path(key), [:read, :binary]) do
      {:ok, io} ->
        data =
          case IO.binread(io, length) do
            :eof -> ""
            data -> data
          end

        File.close(io)
        {:ok, data}

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp parts_dir(key, upload_id), do: path(key) <> ".parts-" <> upload_id

  defp etag(path), do: :crypto.hash(:md5, File.read!(path)) |> Base.encode16(case: :lower)

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
