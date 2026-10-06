defmodule Amauta.AccountsFixtures do
  @moduledoc """
  Personas de prueba. Usan la institución del test (`institution/0`): se
  crea la primera vez que se pide y se reutiliza durante todo el test.
  """
  import Ecto.Query

  alias Amauta.{Accounts, Repo, Scope, Tenancy}

  @doc "Institución del test actual."
  def institution do
    Process.get(:test_institution) ||
      tap(Amauta.Fixtures.institution_fixture(), &Process.put(:test_institution, &1))
  end

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      first_name: "Ada",
      last_name: "Lovelace",
      email: unique_user_email()
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} = Accounts.register_user(institution(), valid_user_attributes(attrs))
    user
  end

  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)

    token =
      extract_user_token(fn url ->
        Accounts.deliver_login_instructions(institution(), user, url)
      end)

    {:ok, {user, _expired_tokens}} = Accounts.login_user_by_magic_link(institution(), token)
    user
  end

  def user_scope_fixture, do: user_scope_fixture(user_fixture())
  def user_scope_fixture(user), do: Scope.for_user(institution(), user)

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(institution(), user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Repo.update_all(
      from(t in Accounts.UserToken, where: t.token == ^token),
      [set: [authenticated_at: authenticated_at]],
      Tenancy.opts(institution())
    )
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    Repo.insert!(user_token, Tenancy.opts(institution()))
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      [set: [inserted_at: dt, authenticated_at: dt]],
      Tenancy.opts(institution())
    )
  end
end
