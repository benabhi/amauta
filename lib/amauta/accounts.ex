defmodule Amauta.Accounts do
  @moduledoc """
  Personas y credenciales de cada institución (base: phx.gen.auth).

  Toda función recibe primero el «tenant» (la institución o un
  `Amauta.Scope`) y opera dentro de su schema. Una persona suspendida no
  puede iniciar sesión, y sus sesiones dejan de ser válidas.
  """
  import Ecto.Query, warn: false

  alias Amauta.Accounts.{User, UserNotifier, UserToken}
  alias Amauta.{Repo, Tenancy}

  ## Consultas

  @doc "Persona por email, o `nil`."
  def get_user_by_email(tenant, email) when is_binary(email) do
    Repo.get_by(User, [email: email], Tenancy.opts(tenant))
  end

  @doc "Persona activa por email y contraseña, o `nil`."
  def get_user_by_email_and_password(tenant, email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, [email: email, status: "active"], Tenancy.opts(tenant))
    if User.valid_password?(user, password), do: user
  end

  @doc "Persona por ID. Falla si no existe."
  def get_user!(tenant, id), do: Repo.get!(User, id, Tenancy.opts(tenant))

  ## Alta

  @doc """
  Da de alta a una persona en la institución, sin contraseña. Entra con un
  enlace mágico, que además confirma su email.
  """
  def register_user(tenant, attrs) do
    tenant
    |> new_user()
    |> User.create_changeset(attrs)
    |> Repo.insert()
  end

  defp new_user(tenant), do: Ecto.put_meta(%User{}, prefix: Tenancy.prefix(tenant))

  ## Ajustes

  @doc """
  Indica si la persona se autenticó hace poco («modo sudo»): por defecto,
  en los últimos 20 minutos. Se exige para los cambios sensibles.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc "Changeset para cambiar el email (ver `User.email_changeset/3`)."
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc "Cambia el email con el token enviado al nuevo email; el token se borra."
  def update_user_email(tenant, user, token) do
    context = "change:#{user.email}"
    opts = Tenancy.opts(tenant)

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query, opts),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email}), opts),
           {_count, _result} <-
             Repo.delete_all(
               from(UserToken, where: [user_id: ^user.id, context: ^context]),
               opts
             ) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc "Changeset para cambiar la contraseña (ver `User.password_changeset/3`)."
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Cambia la contraseña y expira todos los tokens de la persona. Devuelve los
  tokens expirados para desconectar sus sesiones en vivo.
  """
  def update_user_password(tenant, user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens(tenant)
  end

  ## Sesión

  @doc "Genera un token de sesión."
  def generate_user_session_token(tenant, user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token, Tenancy.opts(tenant))
    token
  end

  @doc """
  Persona activa del token de sesión: `{persona, fecha del token}`, o `nil`
  si el token no es válido.
  """
  def get_user_by_session_token(tenant, token) do
    {:ok, query} = UserToken.verify_session_token_query(token)

    query
    |> where([_token, user], user.status == "active")
    |> Repo.one(Tenancy.opts(tenant))
  end

  @doc "Persona del token de enlace mágico, o `nil`."
  def get_user_by_magic_link_token(tenant, token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query, Tenancy.opts(tenant)) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Inicia sesión con un enlace mágico.

    1. Email confirmado: inicia sesión y expira el enlace.
    2. Email sin confirmar y sin contraseña: confirma, inicia sesión y
       expira todos los tokens.
    3. Email sin confirmar con contraseña: no debería ocurrir (las cuentas
       nacen sin contraseña); se rechaza para evitar la fijación de sesión.
  """
  def login_user_by_magic_link(tenant, token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query, Tenancy.opts(tenant)) do
      {%User{status: status}, _token} when status != "active" ->
        {:error, :not_found}

      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise "magic link log in is not allowed for unconfirmed users with a password set"

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens(tenant)

      {user, token} ->
        Repo.delete!(token, Tenancy.opts(tenant))
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc "Envía las instrucciones para confirmar un cambio de email."
  def deliver_user_update_email_instructions(tenant, %User{} = user, current_email, url_fun)
      when is_function(url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")
    Repo.insert!(user_token, Tenancy.opts(tenant))

    UserNotifier.deliver_update_email_instructions(
      user,
      url_fun.(encoded_token),
      locale(tenant, user)
    )
  end

  @doc "Envía el enlace mágico para iniciar sesión."
  def deliver_login_instructions(tenant, %User{} = user, url_fun) when is_function(url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token, Tenancy.opts(tenant))
    UserNotifier.deliver_login_instructions(user, url_fun.(encoded_token), locale(tenant, user))
  end

  @doc "Borra un token de sesión."
  def delete_user_session_token(tenant, token) do
    Repo.delete_all(
      from(UserToken, where: [token: ^token, context: "session"]),
      Tenancy.opts(tenant)
    )

    :ok
  end

  ## Proveedores de identidad (RF-AUT-008)

  @providers %{
    password: Amauta.Accounts.Providers.Password,
    magic_link: Amauta.Accounts.Providers.MagicLink
  }

  @doc "Autentica con un proveedor de identidad (ver `IdentityProvider`)."
  @spec authenticate(Amauta.Platform.Institution.t(), atom(), map()) ::
          Amauta.Accounts.IdentityProvider.result()
  def authenticate(institution, provider, params) do
    Map.fetch!(@providers, provider).authenticate(institution, params)
  end

  ## Dispositivos (RF-AUT-006)

  @doc """
  Registra el dispositivo del inicio de sesión. Devuelve `:new` si la
  persona ya tenía otros y este es nuevo (hay que avisarle), `:first` si es
  el primero y `:known` si ya lo conocíamos.
  """
  @spec register_device(Tenancy.tenant(), User.t(), String.t() | nil) :: :new | :first | :known
  def register_device(tenant, %User{id: user_id}, user_agent) do
    user_agent = String.slice(user_agent || "", 0, 255)
    fingerprint = :crypto.hash(:sha256, user_agent)
    opts = Tenancy.opts(tenant)
    now = DateTime.utc_now(:second)

    existing = from(d in Amauta.Accounts.UserDevice, where: d.user_id == ^user_id)

    {:ok, status} =
      Repo.transact(fn ->
        known? = Repo.exists?(where(existing, fingerprint: ^fingerprint), opts)
        any? = Repo.exists?(existing, opts)

        Repo.insert!(
          %Amauta.Accounts.UserDevice{
            user_id: user_id,
            fingerprint: fingerprint,
            user_agent: user_agent,
            last_seen_at: now
          },
          Keyword.merge(opts,
            on_conflict: [set: [last_seen_at: now]],
            conflict_target: [:user_id, :fingerprint]
          )
        )

        status =
          cond do
            known? -> :known
            any? -> :new
            true -> :first
          end

        {:ok, status}
      end)

    status
  end

  defp locale(%Amauta.Platform.Institution{} = institution, user),
    do: Amauta.Locale.resolve(user, institution)

  defp locale(%{institution: institution}, user), do: locale(institution, user)

  defp update_user_and_delete_all_tokens(changeset, tenant) do
    opts = Tenancy.opts(tenant)

    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset, opts) do
        tokens_to_expire = Repo.all_by(UserToken, [user_id: user.id], opts)
        ids = Enum.map(tokens_to_expire, & &1.id)
        Repo.delete_all(from(t in UserToken, where: t.id in ^ids), opts)

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
