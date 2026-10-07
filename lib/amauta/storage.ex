defmodule Amauta.Storage do
  @moduledoc """
  Almacenamiento de archivos (ERS 8.10). Dos adaptadores: S3 (cualquier
  proveedor compatible; Garage por defecto) y disco local (solo desarrollo y
  pruebas).

  Los archivos no pasan por la aplicación: el navegador sube y descarga con
  URLs prefirmadas de corta duración (RF-ARC-001 y RF-ARC-002).

  Las claves son `inst/{institución}/{entidad}/{uuidv7}/{nombre-saneado}`:
  cada institución tiene su espacio y las claves no se pueden adivinar
  (RF-ARC-007).
  """
  alias Amauta.Platform.Institution

  @type key :: String.t()

  @callback presign_upload(key(), keyword()) :: {:ok, %{url: String.t(), headers: map()}}
  @callback presign_download(key(), keyword()) :: {:ok, String.t()}
  @callback head(key()) ::
              {:ok, %{size: non_neg_integer(), content_type: String.t() | nil}}
              | {:error, :not_found}
  @callback put(key(), iodata(), keyword()) :: :ok | {:error, term()}
  @callback get(key()) :: {:ok, binary()} | {:error, :not_found}
  @callback delete(key()) :: :ok | {:error, term()}

  # Subida por partes (RF-ARC-001): archivos grandes y reanudables.
  @callback start_multipart(key(), keyword()) :: {:ok, String.t()} | {:error, term()}
  @callback presign_part(key(), String.t(), pos_integer(), keyword()) :: {:ok, String.t()}
  @callback list_parts(key(), String.t()) ::
              {:ok, [%{part_number: pos_integer(), etag: String.t(), size: non_neg_integer()}]}
              | {:error, term()}
  @callback complete_multipart(key(), String.t(), [{pos_integer(), String.t()}]) ::
              :ok | {:error, term()}
  @callback abort_multipart(key(), String.t()) :: :ok | {:error, term()}
  # Primeros bytes del objeto, para reconocer su tipo real (RF-ARC-004).
  @callback get_head_bytes(key(), pos_integer()) :: {:ok, binary()} | {:error, :not_found}

  @upload_ttl 15 * 60
  @download_ttl 5 * 60

  @doc """
  Clave nueva para un archivo de una entidad. El nombre se sanea: sin rutas,
  sin caracteres especiales y con un largo acotado.
  """
  @spec key(Institution.t() | %{institution: Institution.t()}, String.t(), String.t()) :: key()
  def key(%{institution: %Institution{} = institution}, entity, filename),
    do: key(institution, entity, filename)

  def key(%Institution{id: id}, entity, filename) when is_binary(entity) do
    true = Regex.match?(~r/^[a-z_]+$/, entity)
    "inst/#{id}/#{entity}/#{Ecto.UUID.generate(version: 7)}/#{sanitize(filename)}"
  end

  @doc "Indica si la clave pertenece a la institución."
  @spec owned_by?(key(), Institution.t()) :: boolean()
  def owned_by?(key, %Institution{id: id}), do: String.starts_with?(key, "inst/#{id}/")

  @doc """
  URL prefirmada para subir con `PUT`. Las cabeceras devueltas (tipo de
  contenido) deben enviarse tal cual.
  """
  def presign_upload(key, opts \\ []),
    do: adapter().presign_upload(key, Keyword.put_new(opts, :expires_in, @upload_ttl))

  @doc """
  URL prefirmada para descargar, de pocos minutos. Con `:filename`, el
  navegador guarda el archivo con ese nombre (RNF-SEG-007).
  """
  def presign_download(key, opts \\ []),
    do: adapter().presign_download(key, Keyword.put_new(opts, :expires_in, @download_ttl))

  def head(key), do: adapter().head(key)
  def put(key, content, opts \\ []), do: adapter().put(key, content, opts)
  def get(key), do: adapter().get(key)
  def delete(key), do: adapter().delete(key)

  @doc "Inicia una subida por partes y devuelve su identificador."
  def start_multipart(key, opts \\ []), do: adapter().start_multipart(key, opts)

  @doc "URL prefirmada para subir una parte con `PUT`."
  def presign_part(key, upload_id, part_number, opts \\ []),
    do:
      adapter().presign_part(
        key,
        upload_id,
        part_number,
        Keyword.put_new(opts, :expires_in, @upload_ttl)
      )

  def list_parts(key, upload_id), do: adapter().list_parts(key, upload_id)

  def complete_multipart(key, upload_id, parts),
    do: adapter().complete_multipart(key, upload_id, parts)

  def abort_multipart(key, upload_id), do: adapter().abort_multipart(key, upload_id)
  def get_head_bytes(key, length), do: adapter().get_head_bytes(key, length)

  @doc false
  def config, do: Application.fetch_env!(:amauta, __MODULE__)

  defp adapter, do: Keyword.fetch!(config(), :adapter)

  @doc false
  def sanitize(filename) do
    sanitized =
      filename
      |> Path.basename()
      |> String.normalize(:nfd)
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.replace(~r/[^A-Za-z0-9._-]+/, "-")
      |> String.replace(~r/-{2,}/, "-")
      |> String.trim("-")
      |> String.slice(0, 120)

    if sanitized in ["", ".", ".."], do: "file", else: sanitized
  end
end
