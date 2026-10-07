defmodule Amauta.Files do
  @moduledoc """
  Archivos con subida directa (RF-ARC-001 a 004 y 007, ADR-0008).

  El recorrido: `start_upload/4` registra el archivo como pendiente y
  devuelve URLs prefirmadas; el navegador sube directo al almacenamiento
  (de una vez o por partes, con progreso y reanudación); `complete_upload/2`
  verifica el objeto, reconoce su tipo real por el contenido y lo deja
  listo o lo rechaza. La descarga es siempre con una URL prefirmada de
  pocos minutos, después de verificar el permiso.

  Solo consultas y operaciones sin permisos: la interfaz usa las acciones
  de `Amauta.Files.Actions`.
  """
  import Ecto.Query

  alias Amauta.Files.{Detect, Purpose, StoredFile}
  alias Amauta.{Repo, Storage, Tenancy}

  # Hasta `single_max`, una sola subida; por encima, por partes de
  # `part_size` (S3 exige partes de al menos 5 MiB, salvo la última). Los
  # tests usan valores chicos (config/test.exs).
  @doc "Tamaño de cada parte en las subidas por partes."
  def part_size, do: setting(:part_size, 8 * 1024 * 1024)

  defp single_max, do: setting(:single_max, 16 * 1024 * 1024)

  defp setting(key, default),
    do: :amauta |> Application.get_env(__MODULE__, []) |> Keyword.get(key, default)

  @doc "Archivo por ID, o `nil`."
  def get(tenant, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(StoredFile, id, Tenancy.opts(tenant))
      :error -> nil
    end
  end

  @doc """
  Registra la subida y arma el plan para el navegador. Valida el tamaño y
  la extensión contra los límites del propósito (RF-ARC-003); el tipo real
  se verifica al completar.

  Si la misma persona ya había empezado a subir el mismo archivo por
  partes, devuelve esa subida con las partes que ya llegaron: el
  navegador sigue desde ahí (reanudación).
  """
  def start_upload(tenant, uploader_id, purpose, attrs) do
    %{filename: filename, size: size} = attrs
    limits = Purpose.limits(purpose)

    cond do
      size <= 0 ->
        {:error, :empty}

      size > limits.max_size ->
        {:error, :too_large}

      Detect.by_extension(filename) not in limits.types ->
        {:error, :type_not_allowed}

      pending = pending_upload(tenant, uploader_id, purpose, attrs) ->
        {:ok, pending, plan(pending)}

      true ->
        create_upload(tenant, uploader_id, purpose, attrs)
    end
  end

  defp pending_upload(tenant, uploader_id, purpose, attrs) do
    from(f in StoredFile,
      where:
        f.uploaded_by_id == ^uploader_id and f.purpose == ^purpose and f.status == "pending" and
          f.filename == ^attrs.filename and f.size == ^attrs.size and not is_nil(f.upload_id),
      order_by: [desc: f.inserted_at],
      limit: 1
    )
    |> where_owner(attrs[:owner_id])
    |> Repo.one(Tenancy.opts(tenant))
  end

  defp where_owner(query, nil), do: where(query, [f], is_nil(f.owner_id))
  defp where_owner(query, owner_id), do: where(query, [f], f.owner_id == ^owner_id)

  defp create_upload(tenant, uploader_id, purpose, attrs) do
    key = Storage.key(tenant, Purpose.entity(purpose), attrs.filename)
    content_type = Detect.by_extension(attrs.filename)

    upload_id =
      if attrs.size > single_max() do
        {:ok, upload_id} = Storage.start_multipart(key, content_type: content_type)
        upload_id
      end

    %StoredFile{}
    |> StoredFile.create_changeset(%{
      purpose: purpose,
      owner_id: attrs[:owner_id],
      key: key,
      filename: attrs.filename,
      declared_type: attrs[:declared_type],
      size: attrs.size,
      upload_id: upload_id,
      uploaded_by_id: uploader_id
    })
    |> Repo.insert(Tenancy.opts(tenant))
    |> case do
      {:ok, file} -> {:ok, file, plan(file)}
      error -> error
    end
  end

  # Plan de subida para el navegador.
  defp plan(%StoredFile{upload_id: nil} = file) do
    content_type = Detect.by_extension(file.filename)

    {:ok, %{url: url, headers: headers}} =
      Storage.presign_upload(file.key, content_type: content_type)

    %{mode: "single", url: url, headers: headers}
  end

  defp plan(%StoredFile{} = file) do
    count = div(file.size + part_size() - 1, part_size())

    done =
      case Storage.list_parts(file.key, file.upload_id) do
        {:ok, parts} ->
          for p <- parts, p.size == part_length(file.size, p.part_number), do: p.part_number

        {:error, _} ->
          []
      end

    parts =
      for number <- 1..count, number not in done do
        {:ok, url} = Storage.presign_part(file.key, file.upload_id, number)
        %{number: number, url: url}
      end

    %{mode: "multipart", part_size: part_size(), parts: parts, done: done}
  end

  defp part_length(size, number) do
    last = div(size + part_size() - 1, part_size())
    if number < last, do: part_size(), else: size - part_size() * (last - 1)
  end

  @doc """
  Verifica la subida: junta las partes, comprueba el tamaño y reconoce el
  tipo real (RF-ARC-004). Si todo está bien, el archivo queda `ready` y se
  vincula según su propósito; si no, queda `rejected` y el objeto se borra.
  Devuelve `{:ok, archivo}` en los dos casos (mirar su `status` y su
  `rejection_reason`), o `{:error, :not_pending}`.
  """
  def complete_upload(tenant, %StoredFile{status: "pending"} = file) do
    with :ok <- finish_parts(file),
         {:ok, %{size: size}} <- Storage.head(file.key),
         :ok <- if(size == file.size, do: :ok, else: {:error, :incomplete}),
         {:ok, head} <- Storage.get_head_bytes(file.key, Detect.head_size()),
         {:ok, type} <- Detect.detect(head, file.filename),
         :ok <-
           if(type in Purpose.limits(file.purpose).types,
             do: :ok,
             else: {:error, :type_not_allowed}
           ) do
      {:ok, file} =
        file
        |> Ecto.Changeset.change(status: "ready", content_type: type, upload_id: nil)
        |> Repo.update(Tenancy.opts(tenant))

      :ok = Purpose.attach(tenant, file)
      {:ok, file}
    else
      {:error, :not_found} -> reject(tenant, file, :not_uploaded)
      {:error, reason} -> reject(tenant, file, reason)
    end
  end

  def complete_upload(_tenant, %StoredFile{}), do: {:error, :not_pending}

  defp finish_parts(%StoredFile{upload_id: nil}), do: :ok

  defp finish_parts(%StoredFile{upload_id: upload_id} = file) do
    count = div(file.size + part_size() - 1, part_size())

    with {:ok, parts} <- Storage.list_parts(file.key, upload_id) do
      if Enum.map(parts, & &1.part_number) == Enum.to_list(1..count) do
        Storage.complete_multipart(
          file.key,
          upload_id,
          Enum.map(parts, &{&1.part_number, &1.etag})
        )
      else
        {:error, :incomplete}
      end
    end
  end

  defp reject(tenant, file, reason) do
    if file.upload_id, do: Storage.abort_multipart(file.key, file.upload_id)
    Storage.delete(file.key)

    # Se devuelve :ok para que el rechazo quede registrado aunque la
    # subida no haya servido (la acción no revierte la transacción).
    {:ok,
     file
     |> Ecto.Changeset.change(status: "rejected", rejection_reason: Atom.to_string(reason))
     |> Repo.update!(Tenancy.opts(tenant))}
  end

  @doc "Borra el objeto y deja el archivo rechazado (por ejemplo, una foto reemplazada)."
  def discard(tenant, %StoredFile{} = file) do
    Storage.delete(file.key)

    file
    |> Ecto.Changeset.change(status: "rejected", rejection_reason: "replaced")
    |> Repo.update!(Tenancy.opts(tenant))

    :ok
  end

  @doc """
  URL de descarga de pocos minutos (RF-ARC-002). Con `download: true`, el
  navegador lo guarda con su nombre original; si no, lo muestra (imágenes).
  """
  def download_url(%StoredFile{status: "ready"} = file, opts \\ []) do
    opts = if opts[:download], do: [filename: file.filename], else: []
    Storage.presign_download(file.key, opts)
  end
end
