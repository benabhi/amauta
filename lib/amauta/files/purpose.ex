defmodule Amauta.Files.Purpose do
  @moduledoc """
  Para qué es cada archivo: de eso salen sus límites (RF-ARC-003), quién
  puede subirlo y verlo, y qué pasa cuando queda listo. En el MVP solo
  existían la foto de perfil y los adjuntos del tablón; los materiales y las
  entregas se suman en H2 y H3 como nuevos propósitos.

  Los límites de la instancia (`config :amauta, Amauta.Files`) acotan a
  los de cada propósito: vale el más estricto.
  """
  alias Amauta.Accounts.User
  alias Amauta.Courses
  alias Amauta.Files.StoredFile
  alias Amauta.{Authorization, Feed, Repo, Scope, Tenancy}

  @images ~w(image/png image/jpeg image/gif image/webp)

  # Adjuntos del tablón: lo que se comparte en un curso (documentos,
  # imágenes, audio, video, planillas y presentaciones).
  @documents Amauta.Files.Detect.known_types()

  @purposes %{
    "avatar" => %{types: @images, max_size: 5 * 1024 * 1024, entity: "avatars"},
    "feed_attachment" => %{types: @documents, max_size: 50 * 1024 * 1024, entity: "feed"}
  }

  @doc "Propósitos conocidos."
  def all, do: Map.keys(@purposes)

  @doc "Tipos y tamaño máximo del propósito, acotados por los de la instancia."
  def limits(purpose) do
    %{types: types, max_size: max_size} = Map.fetch!(@purposes, purpose)
    instance = Application.get_env(:amauta, Amauta.Files, [])

    %{
      types: Enum.filter(types, &(&1 in Keyword.get(instance, :allowed_types, types))),
      max_size: min(max_size, Keyword.get(instance, :max_size, max_size))
    }
  end

  @doc "Segmento de la clave en el almacenamiento (`inst/{id}/{entidad}/…`)."
  def entity(purpose), do: Map.fetch!(@purposes, purpose).entity

  @doc """
  Puede subir un archivo para ese dueño: la foto propia, o la de otra
  persona si gestiona las personas de la institución.
  """
  @spec authorize_upload(Scope.t(), String.t(), Ecto.UUID.t() | nil) :: :ok | {:error, :forbidden}
  def authorize_upload(%Scope{user: nil}, _purpose, _owner_id), do: {:error, :forbidden}

  def authorize_upload(%Scope{user: %{id: id}}, "avatar", id), do: :ok

  def authorize_upload(scope, "avatar", _owner_id),
    do: Authorization.authorize(scope, "institution.users.manage")

  # Adjuntos del tablón: el dueño es el curso donde se van a publicar.
  def authorize_upload(scope, "feed_attachment", course_id) do
    case course_id && Courses.get(scope, course_id) do
      nil -> {:error, :forbidden}
      course -> if Feed.can_attach?(scope, course), do: :ok, else: {:error, :forbidden}
    end
  end

  @doc """
  Puede ver el archivo: las fotos de perfil, cualquier persona de la
  institución; los adjuntos del tablón, quien ve la publicación.
  """
  @spec can_view?(Scope.t(), StoredFile.t()) :: boolean()
  def can_view?(%Scope{user: nil}, _file), do: false
  def can_view?(_scope, %StoredFile{purpose: "avatar", status: "ready"}), do: true

  def can_view?(scope, %StoredFile{purpose: "feed_attachment", status: "ready"} = file),
    do: Feed.can_view_attachment?(scope, file)

  def can_view?(_scope, _file), do: false

  @doc """
  Lo que pasa cuando el archivo queda listo. La foto nueva reemplaza a la
  anterior, que se borra del almacenamiento.
  """
  # Los adjuntos del tablón se vinculan al publicar (`Amauta.Feed.sync_attachments/4`).
  def attach(_tenant, %StoredFile{purpose: "feed_attachment"}), do: :ok

  def attach(tenant, %StoredFile{purpose: "avatar", owner_id: user_id} = file) do
    opts = Tenancy.opts(tenant)
    user = Repo.get!(User, user_id, opts)
    previous = user.avatar_file_id && Repo.get(StoredFile, user.avatar_file_id, opts)

    {:ok, _user} =
      user
      |> Ecto.Changeset.change(avatar_file_id: file.id)
      |> Repo.update(opts)

    if previous, do: Amauta.Files.discard(tenant, previous)
    :ok
  end
end
