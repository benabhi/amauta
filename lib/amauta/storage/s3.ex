defmodule Amauta.Storage.S3 do
  @moduledoc """
  Adaptador S3 de `Amauta.Storage` (ex_aws). Las URLs prefirmadas se firman
  con el host público, el que usa el navegador; el resto de las operaciones
  van por el endpoint interno.
  """
  @behaviour Amauta.Storage

  alias ExAws.S3

  @impl true
  def presign_upload(key, opts) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    {:ok, url} =
      S3.presigned_url(public_config(), :put, bucket(), key,
        expires_in: Keyword.fetch!(opts, :expires_in),
        headers: [{"content-type", content_type}]
      )

    {:ok, %{url: url, headers: %{"content-type" => content_type}}}
  end

  @impl true
  def presign_download(key, opts) do
    query =
      case Keyword.get(opts, :filename) do
        nil -> []
        name -> [{"response-content-disposition", ~s(attachment; filename="#{name}")}]
      end

    S3.presigned_url(public_config(), :get, bucket(), key,
      expires_in: Keyword.fetch!(opts, :expires_in),
      query_params: query
    )
  end

  @impl true
  def head(key) do
    case bucket() |> S3.head_object(key) |> ExAws.request() do
      {:ok, %{headers: headers}} ->
        headers = Map.new(headers, fn {k, v} -> {String.downcase(k), v} end)

        {:ok,
         %{
           size:
             headers |> Map.get("content-length", "0") |> header_value() |> String.to_integer(),
           content_type: headers |> Map.get("content-type") |> header_value()
         }}

      {:error, {:http_error, 404, _}} ->
        {:error, :not_found}
    end
  end

  @impl true
  def put(key, content, opts) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    case bucket()
         |> S3.put_object(key, IO.iodata_to_binary(content), content_type: content_type)
         |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get(key) do
    case bucket() |> S3.get_object(key) |> ExAws.request() do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, {:http_error, 404, _}} -> {:error, :not_found}
    end
  end

  @impl true
  def delete(key) do
    case bucket() |> S3.delete_object(key) |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def start_multipart(key, opts) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    case bucket()
         |> S3.initiate_multipart_upload(key, content_type: content_type)
         |> ExAws.request() do
      {:ok, %{body: %{upload_id: upload_id}}} -> {:ok, upload_id}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def presign_part(key, upload_id, part_number, opts) do
    S3.presigned_url(public_config(), :put, bucket(), key,
      expires_in: Keyword.fetch!(opts, :expires_in),
      query_params: [{"partNumber", Integer.to_string(part_number)}, {"uploadId", upload_id}]
    )
  end

  @impl true
  def list_parts(key, upload_id) do
    case bucket() |> S3.list_parts(key, upload_id) |> ExAws.request() do
      {:ok, %{body: %{parts: parts}}} ->
        {:ok,
         for part <- parts do
           %{
             part_number: String.to_integer(part.part_number),
             etag: part.etag,
             size: String.to_integer(part.size)
           }
         end}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def complete_multipart(key, upload_id, parts) do
    case bucket() |> S3.complete_multipart_upload(key, upload_id, parts) |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def abort_multipart(key, upload_id) do
    case bucket() |> S3.abort_multipart_upload(key, upload_id) |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_head_bytes(key, length) do
    case bucket() |> S3.get_object(key, range: "bytes=0-#{length - 1}") |> ExAws.request() do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, {:http_error, 404, _}} -> {:error, :not_found}
      {:error, {:http_error, 416, _}} -> {:ok, ""}
    end
  end

  defp bucket, do: Keyword.fetch!(Amauta.Storage.config(), :bucket)

  defp public_config do
    storage = Amauta.Storage.config()

    ExAws.Config.new(:s3,
      scheme: Keyword.fetch!(storage, :public_scheme),
      host: Keyword.fetch!(storage, :public_host),
      port: Keyword.fetch!(storage, :public_port)
    )
  end

  defp header_value([value | _]), do: value
  defp header_value(value), do: value
end
