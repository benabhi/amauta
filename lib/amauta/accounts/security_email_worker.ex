defmodule Amauta.Accounts.SecurityEmailWorker do
  @moduledoc """
  Avisos de seguridad por email (RF-AUT-006, RNF-SEG-018): inicio de sesión
  desde un dispositivo nuevo y cuenta bloqueada por intentos fallidos.
  """
  use Amauta.Worker, queue: :mailers, max_attempts: 5

  alias Amauta.Accounts.{User, UserNotifier}
  alias Amauta.{Locale, Repo, Tenancy}

  @impl Amauta.Worker
  def perform_for(institution, %{"user_id" => user_id, "kind" => kind} = args) do
    case Repo.get(User, user_id, Tenancy.opts(institution)) do
      nil ->
        {:cancel, :user_not_found}

      user ->
        locale = Locale.resolve(user, institution)

        {:ok, _} =
          case kind do
            "new_device" ->
              UserNotifier.deliver_new_device_notice(user, args["user_agent"], locale)

            "account_locked" ->
              UserNotifier.deliver_account_locked_notice(user, locale)
          end

        :ok
    end
  end
end
