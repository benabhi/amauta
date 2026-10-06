defmodule Amauta.Accounts.InvitationWorker do
  @moduledoc """
  Envía la invitación a una persona dada de alta por la institución: un
  enlace mágico que confirma su cuenta y la deja entrar (RF-INS-004).

  La URL la arma la capa web (`config :amauta, :login_url`), así el dominio
  no depende de ella.
  """
  use Amauta.Worker, queue: :mailers, max_attempts: 5

  alias Amauta.Accounts.{User, UserNotifier, UserToken}
  alias Amauta.{Locale, Repo, Tenancy}

  @impl Amauta.Worker
  def perform_for(institution, %{"user_id" => user_id}) do
    case Repo.get(User, user_id, Tenancy.opts(institution)) do
      %User{status: "invited"} = user ->
        {encoded, token} = UserToken.build_email_token(user, "invitation")
        Repo.insert!(token, Tenancy.opts(institution))

        {:ok, _} =
          UserNotifier.deliver_invitation(
            user,
            institution,
            login_url(institution, encoded),
            Locale.resolve(user, institution)
          )

        :ok

      # Ya entró, la suspendieron o la borraron: no hay nada que enviar.
      _ ->
        {:cancel, :not_invited}
    end
  end

  defp login_url(institution, token) do
    {module, function} = Application.fetch_env!(:amauta, :login_url)
    apply(module, function, [institution, token])
  end
end
