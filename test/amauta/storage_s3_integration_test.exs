defmodule Amauta.StorageS3IntegrationTest do
  @moduledoc """
  Pruebas contra Garage real. Se excluyen por defecto; en el entorno de
  desarrollo: `bin/dev mix test --only integration` (usa las variables S3_*
  del contenedor).
  """
  use ExUnit.Case, async: false

  alias Amauta.Platform.Institution
  alias Amauta.Storage

  @moduletag :integration

  setup do
    previous = Application.fetch_env!(:amauta, Storage)
    endpoint = URI.parse(System.fetch_env!("S3_ENDPOINT"))

    Application.put_env(:ex_aws, :access_key_id, System.fetch_env!("S3_ACCESS_KEY_ID"))
    Application.put_env(:ex_aws, :secret_access_key, System.fetch_env!("S3_SECRET_ACCESS_KEY"))
    Application.put_env(:ex_aws, :region, "garage")

    Application.put_env(:ex_aws, :s3,
      scheme: "#{endpoint.scheme}://",
      host: endpoint.host,
      port: endpoint.port,
      region: "garage"
    )

    # Dentro del contenedor, el host público tampoco es localhost.
    Application.put_env(:amauta, Storage,
      adapter: Storage.S3,
      bucket: System.fetch_env!("S3_BUCKET"),
      public_scheme: "#{endpoint.scheme}://",
      public_host: endpoint.host,
      public_port: endpoint.port
    )

    on_exit(fn -> Application.put_env(:amauta, Storage, previous) end)
    %{institution: %Institution{id: Ecto.UUID.generate()}}
  end

  test "guarda, describe, lee y borra", %{institution: institution} do
    key = Storage.key(institution, "files", "hola.txt")

    assert :ok = Storage.put(key, "hola Garage", content_type: "text/plain")
    assert {:ok, %{size: 11, content_type: "text/plain"}} = Storage.head(key)
    assert {:ok, "hola Garage"} = Storage.get(key)
    assert :ok = Storage.delete(key)
    assert {:error, :not_found} = Storage.head(key)
  end

  test "sube y descarga con URLs prefirmadas", %{institution: institution} do
    key = Storage.key(institution, "submissions", "entrega.pdf")

    {:ok, %{url: upload_url, headers: headers}} =
      Storage.presign_upload(key, content_type: "application/pdf")

    assert %{status: 200} = Req.put!(upload_url, body: "%PDF-1.7 prueba", headers: headers)
    assert {:ok, %{size: 15, content_type: "application/pdf"}} = Storage.head(key)

    {:ok, download_url} = Storage.presign_download(key, filename: "entrega.pdf")
    response = Req.get!(download_url)
    assert response.body == "%PDF-1.7 prueba"
    assert [disposition] = Req.Response.get_header(response, "content-disposition")
    assert disposition =~ "entrega.pdf"

    Storage.delete(key)
  end

  test "una URL prefirmada no sirve para otra clave", %{institution: institution} do
    key = Storage.key(institution, "files", "a.txt")
    {:ok, %{url: url, headers: headers}} = Storage.presign_upload(key, content_type: "text/plain")
    tampered = String.replace(url, "a.txt", "b.txt")

    assert %{status: 403} = Req.put!(tampered, body: "x", headers: headers, retry: false)
  end
end
