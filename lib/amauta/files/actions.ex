defmodule Amauta.Files.Actions.StartUpload do
  @moduledoc """
  Pide una subida directa (RF-ARC-001): registra el archivo como pendiente
  y devuelve el plan con las URLs prefirmadas. No se audita: lo que importa
  es la subida completada.
  """
  use Amauta.Action,
    name: "files.upload.start",
    description: "Pide URLs para subir un archivo directo al almacenamiento.",
    params: [
      purpose: {:string, required: true},
      owner_id: Ecto.UUID,
      filename: {:string, required: true},
      size: {:integer, required: true},
      declared_type: :string
    ]

  import Ecto.Changeset

  alias Amauta.Files
  alias Amauta.Files.Purpose

  @impl true
  def validate(changeset) do
    changeset
    |> validate_inclusion(:purpose, Purpose.all())
    |> validate_length(:filename, max: 255)
  end

  @impl true
  def authorize(scope, input),
    do: Purpose.authorize_upload(scope, input.purpose, owner(scope, input))

  @impl true
  def run(scope, input) do
    attrs = %{
      filename: input.filename,
      size: input.size,
      declared_type: input[:declared_type],
      owner_id: owner(scope, input)
    }

    case Files.start_upload(scope, scope.user.id, input.purpose, attrs) do
      {:ok, file, plan} -> {:ok, %{file: file, plan: plan}}
      error -> error
    end
  end

  @impl true
  def audit(_scope, _input, _result), do: :skip

  # La foto de perfil es, por defecto, la propia.
  defp owner(scope, %{purpose: "avatar"} = input), do: input[:owner_id] || scope.user.id
  defp owner(_scope, input), do: input[:owner_id]
end

defmodule Amauta.Files.Actions.CompleteUpload do
  @moduledoc """
  Confirma una subida: verifica el objeto y su tipo real (RF-ARC-004) y lo
  deja listo, o lo rechaza y borra. Solo quien la empezó puede confirmarla.
  """
  use Amauta.Action,
    name: "files.upload.complete",
    description: "Confirma y verifica una subida directa.",
    params: [file_id: {Ecto.UUID, required: true}]

  alias Amauta.Files

  @impl true
  def authorize(%{user: %{id: user_id}} = scope, %{file_id: id}) do
    case Files.get(scope, id) do
      nil -> {:error, :not_found}
      %{uploaded_by_id: ^user_id} -> :ok
      _other -> {:error, :forbidden}
    end
  end

  def authorize(_scope, _input), do: {:error, :forbidden}

  @impl true
  def run(scope, %{file_id: id}), do: Files.complete_upload(scope, Files.get(scope, id))

  @impl true
  def audit(_scope, _input, file),
    do:
      {file,
       %{
         purpose: file.purpose,
         filename: file.filename,
         size: file.size,
         content_type: file.content_type,
         status: file.status,
         rejection_reason: file.rejection_reason
       }}
end

defmodule Amauta.Files.Actions.RemoveAvatar do
  @moduledoc "Quita la foto de perfil (la propia, o la de otra persona con permiso)."
  use Amauta.Action,
    name: "files.avatar.remove",
    description: "Quita la foto de perfil.",
    params: [user_id: {Ecto.UUID, required: true}]

  alias Amauta.Accounts.User
  alias Amauta.Files.Purpose
  alias Amauta.{Files, Repo, Tenancy}

  @impl true
  def authorize(scope, %{user_id: user_id}),
    do: Purpose.authorize_upload(scope, "avatar", user_id)

  @impl true
  def run(scope, %{user_id: user_id}) do
    opts = Tenancy.opts(scope)

    case Repo.get(User, user_id, opts) do
      nil ->
        {:error, :not_found}

      %User{avatar_file_id: nil} = user ->
        {:ok, user}

      user ->
        file = Files.get(scope, user.avatar_file_id)
        {:ok, user} = user |> Ecto.Changeset.change(avatar_file_id: nil) |> Repo.update(opts)
        if file, do: Files.discard(scope, file)
        {:ok, user}
    end
  end
end
