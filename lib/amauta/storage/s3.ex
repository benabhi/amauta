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
