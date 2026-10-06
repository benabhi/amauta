defmodule Amauta.Accounts.Actions.Helpers do
  @moduledoc false
  alias Amauta.{Authorization, Repo, Tenancy}
  alias Amauta.Accounts.{InvitationWorker, User, UserToken}

  def authorize_manage(scope), do: Authorization.authorize(scope, "institution.users.manage")

  def fetch_user(scope, id) do
    case Repo.get(User, id, Tenancy.opts(scope)) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def invitation(scope, user), do: InvitationWorker.new_for(scope, %{"user_id" => user.id})

  @doc """
  Cierra todas las sesiones de una persona: borra sus tokens y desconecta
  sus LiveViews (el mismo mensaje que usa `AmautaWeb.UserAuth`).
  """
  def end_sessions(scope, user) do
    import Ecto.Query

    tokens =
      Repo.all(
        from(t in UserToken, where: t.user_id == ^user.id and t.context == "session"),
        Tenancy.opts(scope)
      )

    Repo.delete_all(from(t in UserToken, where: t.user_id == ^user.id), Tenancy.opts(scope))

    for %{token: token} <- tokens do
      topic = "users_sessions:#{Base.url_encode64(token)}"

      Phoenix.PubSub.broadcast(Amauta.PubSub, topic, %Phoenix.Socket.Broadcast{
        topic: topic,
        event: "disconnect",
        payload: %{}
      })
    end

    :ok
  end
end

defmodule Amauta.Accounts.Actions.CreateUser do
  @moduledoc "Alta manual de una persona, con invitación por email (RF-INS-004)."
  use Amauta.Action,
    name: "accounts.user.create",
    description: "Da de alta a una persona en la institución y la invita por email.",
    params: [
      first_name: {:string, required: true},
      last_name: {:string, required: true},
      email: {:string, required: true},
      preferred_name: :string,
      timezone: :string,
      send_invitation: :boolean
    ]

  alias Amauta.Accounts
  alias Amauta.Accounts.Actions.Helpers

  @impl true
  def authorize(scope, _input), do: Helpers.authorize_manage(scope)

  @impl true
  def run(scope, input), do: Accounts.register_user(scope, Map.drop(input, [:send_invitation]))

  @impl true
  def effects(scope, input, user) do
    if Map.get(input, :send_invitation, true), do: [Helpers.invitation(scope, user)], else: []
  end
end

defmodule Amauta.Accounts.Actions.UpdateUser do
  @moduledoc "Edición del perfil de una persona por la institución (RF-USR-001)."
  use Amauta.Action,
    name: "accounts.user.update",
    description: "Edita el perfil de una persona.",
    params: [
      user_id: {Ecto.UUID, required: true},
      first_name: :string,
      last_name: :string,
      preferred_name: :string,
      timezone: :string
    ]

  alias Amauta.Accounts.Actions.Helpers
  alias Amauta.Accounts.User
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(scope, _input), do: Helpers.authorize_manage(scope)

  @impl true
  def run(scope, %{user_id: id} = input) do
    with {:ok, user} <- Helpers.fetch_user(scope, id) do
      user
      |> User.profile_changeset(Map.delete(input, :user_id))
      |> Repo.update(Tenancy.opts(scope))
    end
  end
end

defmodule Amauta.Accounts.Actions.SuspendUser do
  @moduledoc """
  Suspende a una persona: no puede entrar y se cierran sus sesiones
  (RF-USR-003). Nadie puede suspenderse a sí mismo.
  """
  use Amauta.Action,
    name: "accounts.user.suspend",
    description: "Suspende a una persona y cierra sus sesiones.",
    params: [user_id: {Ecto.UUID, required: true}]

  alias Amauta.Accounts.Actions.Helpers
  alias Amauta.Accounts.User
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(%{user: %{id: id}}, %{user_id: id}), do: {:error, :forbidden}
  def authorize(scope, _input), do: Helpers.authorize_manage(scope)

  @impl true
  def run(scope, %{user_id: id}) do
    with {:ok, user} <- Helpers.fetch_user(scope, id),
         {:ok, user} <-
           user |> User.status_changeset("suspended") |> Repo.update(Tenancy.opts(scope)) do
      Helpers.end_sessions(scope, user)
      {:ok, user}
    end
  end
end

defmodule Amauta.Accounts.Actions.ReactivateUser do
  @moduledoc "Reactiva a una persona suspendida: vuelve a activa, o a invitada si nunca entró."
  use Amauta.Action,
    name: "accounts.user.reactivate",
    description: "Reactiva a una persona suspendida.",
    params: [user_id: {Ecto.UUID, required: true}]

  alias Amauta.Accounts.Actions.Helpers
  alias Amauta.Accounts.User
  alias Amauta.{Repo, Tenancy}

  @impl true
  def authorize(scope, _input), do: Helpers.authorize_manage(scope)

  @impl true
  def run(scope, %{user_id: id}) do
    with {:ok, user} <- Helpers.fetch_user(scope, id) do
      status = if user.confirmed_at, do: "active", else: "invited"
      user |> User.status_changeset(status) |> Repo.update(Tenancy.opts(scope))
    end
  end
end

defmodule Amauta.Accounts.Actions.ResendInvitation do
  @moduledoc "Vuelve a enviar la invitación a una persona que todavía no entró."
  use Amauta.Action,
    name: "accounts.user.resend_invitation",
    description: "Reenvía la invitación por email.",
    params: [user_id: {Ecto.UUID, required: true}]

  alias Amauta.Accounts.Actions.Helpers

  @impl true
  def authorize(scope, _input), do: Helpers.authorize_manage(scope)

  @impl true
  def run(scope, %{user_id: id}) do
    case Helpers.fetch_user(scope, id) do
      {:ok, %{status: "invited"} = user} -> {:ok, user}
      {:ok, _user} -> {:error, :not_invited}
      error -> error
    end
  end

  @impl true
  def effects(scope, _input, user), do: [Helpers.invitation(scope, user)]
end
