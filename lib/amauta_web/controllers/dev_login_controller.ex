defmodule AmautaWeb.DevLoginController do
  @moduledoc """
  Inicio de sesión rápido con las personas de ejemplo, por rol (RNF-DEV-009).
  Las rutas solo existen con `config :amauta, dev_login: true`, que se
  activa únicamente en desarrollo.
  """
  use AmautaWeb, :controller

  import Ecto.Query

  alias Amauta.{Accounts, Authorization, Repo, Tenancy}
  alias Amauta.Accounts.User
  alias Amauta.Authorization.Roles
  alias AmautaWeb.UserAuth

  def index(conn, _params) do
    institution = conn.assigns.current_institution

    people =
      from(u in User, order_by: [u.first_name, u.last_name], limit: 50)
      |> Repo.all(Tenancy.opts(institution))
      |> Enum.map(fn user ->
        roles =
          institution
          |> Authorization.list_assignments(user.id)
          |> Enum.map(&Roles.name(&1.role))

        {user, roles}
      end)

    conn
    |> put_layout(false)
    |> put_view(AmautaWeb.DevLoginHTML)
    |> render(:index, people: people, current_scope: conn.assigns.current_scope)
  end

  def create(conn, %{"user_id" => user_id}) do
    user = Accounts.get_user!(conn.assigns.current_institution, user_id)
    UserAuth.log_in_user(conn, user)
  end
end

defmodule AmautaWeb.DevLoginHTML do
  @moduledoc false
  use AmautaWeb, :html

  alias Amauta.Accounts.User
  alias AmautaWeb.Paths

  def index(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width="sm">
      <.header>
        {gettext("Log in as…")}
        <:subtitle>
          {gettext("Development only.")} {@current_scope.institution.name}
        </:subtitle>
      </.header>

      <.card>
        <ul class="divide-y divide-line">
          <li :for={{user, roles} <- @people} class="flex items-center gap-3 py-3">
            <.avatar name={User.display_name(user)} />
            <div class="min-w-0 flex-1">
              <p class="font-semibold">{User.display_name(user)}</p>
              <p class="truncate text-sm text-ink-muted">{user.email}</p>
              <div class="mt-1 flex flex-wrap gap-1">
                <.badge :for={role <- roles} family="anil">{role}</.badge>
              </div>
            </div>
            <.form
              for={%{}}
              action={Paths.dev_login(@current_scope, user)}
              method="post"
            >
              <.button size="sm" variant="secondary" icon="sign-in">{gettext("Log in")}</.button>
            </.form>
          </li>
        </ul>
      </.card>
    </Layouts.app>
    """
  end
end
