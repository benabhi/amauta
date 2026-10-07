defmodule Amauta.Notifications.EmailDigestWorker do
  @moduledoc """
  Email agrupado de notificaciones (RF-EML-004): cuando a una persona le
  llega una notificación por email, se agenda este trabajo al final de una
  ventana breve (`config :amauta, Amauta.Notifications, email_window:`). Si
  en ese rato llegan más, no se agenda otro: el mismo trabajo junta todas
  las pendientes en un solo email.
  """
  use Amauta.Worker,
    queue: :mailers,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:institution_id, :user_id],
      states: [:scheduled, :available]
    ]

  import Ecto.Query

  alias Amauta.Accounts.User
  alias Amauta.Notifications.{Email, Notification}
  alias Amauta.{Locale, Repo, Tenancy}

  @doc "Agenda el email de la persona, si no hay uno ya agendado."
  def schedule(tenant, user_id) do
    window =
      Application.get_env(:amauta, Amauta.Notifications, []) |> Keyword.get(:email_window, 600)

    tenant |> new_for(%{"user_id" => user_id}, schedule_in: window) |> Oban.insert!()
  end

  @impl Amauta.Worker
  def perform_for(institution, %{"user_id" => user_id}) do
    opts = Tenancy.opts(institution)

    with %User{status: status} = user when status in ~w(active invited) <-
           Repo.get(User, user_id, opts),
         [_ | _] = notifications <- pending(institution, user_id) do
      Gettext.with_locale(AmautaWeb.Gettext, Locale.resolve(user, institution), fn ->
        user
        |> Email.digest(institution, notifications)
        |> Amauta.Mail.deliver_later(:notification)
      end)

      ids = Enum.map(notifications, & &1.id)

      from(n in Notification, where: n.id in ^ids)
      |> Repo.update_all([set: [email_pending: false, emailed_at: DateTime.utc_now()]], opts)

      :ok
    else
      _ -> :ok
    end
  end

  defp pending(institution, user_id) do
    from(n in Notification,
      where: n.user_id == ^user_id and n.email_pending,
      order_by: [asc: n.updated_at],
      preload: [:actor, :course]
    )
    |> Repo.all(Tenancy.opts(institution))
  end
end
