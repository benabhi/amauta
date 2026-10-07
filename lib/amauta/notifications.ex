defmodule Amauta.Notifications do
  @moduledoc """
  Notificaciones (capacidad C12): cada aviso nace de un evento del
  catálogo (`Amauta.Notifications.Catalog`), se dirige a personas con un
  motivo («por ser estudiante de…») y se entrega por los canales que cada
  una eligió (RF-NOT-001 a 004).

  La entrega la hace `Amauta.Notifications.DeliverWorker`, en segundo plano
  y por lotes (RF-NOT-008): las acciones solo encolan el trabajo. Las no
  leídas del mismo grupo se suman en una sola notificación.
  """
  import Ecto.Query

  alias Amauta.Notifications.{Catalog, Notification, Preference}
  alias Amauta.{Repo, Scope, Tenancy}

  @page 50

  ## Tiempo real

  @doc "Tema de las notificaciones de una persona."
  def topic(tenant, user_id),
    do: "notifications:#{Amauta.Worker.institution_id(tenant)}:#{user_id}"

  @doc "Se suscribe a las notificaciones de la persona del scope."
  def subscribe(%Scope{user: %{id: user_id}} = scope),
    do: Phoenix.PubSub.subscribe(Amauta.PubSub, topic(scope, user_id))

  defp broadcast(tenant, user_ids) do
    for id <- user_ids,
        do: Phoenix.PubSub.broadcast(Amauta.PubSub, topic(tenant, id), {:notifications, :changed})
  end

  ## Preferencias (RF-NOT-004 y RF-EML-005)

  @doc """
  Preferencias de la persona: `%{{evento, canal} => boolean}` para todo el
  catálogo, con los valores por defecto donde no eligió nada.
  """
  def preferences(%Scope{user: %{id: user_id}} = scope) do
    chosen =
      from(p in Preference,
        where: p.user_id == ^user_id,
        select: {{p.event, p.channel}, p.enabled}
      )
      |> Repo.all(Tenancy.opts(scope))
      |> Map.new()

    for event <- Catalog.events(), channel <- Catalog.channels(), into: %{} do
      key = {event, channel}
      {key, Map.get(chosen, key, Catalog.default(event, channel))}
    end
  end

  @doc "Elige si recibir un evento por un canal."
  def set_preference(%Scope{user: %{id: user_id}} = scope, event, channel, enabled)
      when is_boolean(enabled) do
    if Catalog.event?(event) and channel in Catalog.channels() do
      %Preference{user_id: user_id, event: event, channel: channel, enabled: enabled}
      |> Repo.insert(
        Tenancy.opts(scope) ++
          [
            on_conflict: [set: [enabled: enabled, updated_at: DateTime.utc_now()]],
            conflict_target: [:user_id, :event, :channel]
          ]
      )
    else
      {:error, :invalid}
    end
  end

  # Canales activos de cada persona para un evento.
  defp channels_for(tenant, user_ids, event) do
    chosen =
      from(p in Preference,
        where: p.user_id in ^user_ids and p.event == ^event,
        select: {{p.user_id, p.channel}, p.enabled}
      )
      |> Repo.all(Tenancy.opts(tenant))
      |> Map.new()

    Map.new(user_ids, fn id ->
      channels =
        Enum.filter(Catalog.channels(), fn channel ->
          Map.get(chosen, {id, channel}, Catalog.default(event, channel))
        end)

      {id, channels}
    end)
  end

  ## Entrega

  @doc """
  Entrega un evento a sus destinatarios (`[{user_id, reason}]`), según los
  canales de cada uno. `attrs`: `:course_id`, `:actor_id`, `:data`, `:url` y
  `:group_key`. No se notifica a quien hizo la acción, ni dos veces a la
  misma persona (gana el primer motivo).

  Devuelve los IDs de quienes tienen un email pendiente.
  """
  def deliver(tenant, event, recipients, attrs) do
    actor = attrs[:actor_id]

    recipients =
      recipients
      |> Enum.reject(fn {id, _reason} -> id == actor end)
      |> Enum.uniq_by(&elem(&1, 0))

    channels = channels_for(tenant, Enum.map(recipients, &elem(&1, 0)), event)
    now = DateTime.utc_now()

    rows =
      for {user_id, reason} <- recipients,
          channels[user_id] != [] do
        platform = "platform" in channels[user_id]
        email = "email" in channels[user_id]

        %{
          id: Ecto.UUID.generate(version: 7),
          user_id: user_id,
          event: event,
          course_id: attrs[:course_id],
          actor_id: actor,
          data: attrs[:data] || %{},
          url: attrs[:url],
          reason: reason,
          group_key: attrs[:group_key] || "#{event}:#{Ecto.UUID.generate()}",
          count: 1,
          # Sin el canal de la plataforma, solo espera el email.
          read_at: if(platform, do: nil, else: now),
          email_pending: email,
          inserted_at: now,
          updated_at: now
        }
      end

    rows
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(
        Notification,
        chunk,
        Tenancy.opts(tenant) ++
          [
            # Una no leída del mismo grupo suma uno en lugar de duplicarse.
            on_conflict:
              from(n in Notification,
                update: [
                  inc: [count: 1],
                  set: [
                    actor_id: fragment("EXCLUDED.actor_id"),
                    data: fragment("EXCLUDED.data"),
                    url: fragment("EXCLUDED.url"),
                    email_pending: fragment("? OR EXCLUDED.email_pending", n.email_pending),
                    updated_at: fragment("EXCLUDED.updated_at")
                  ]
                ]
              ),
            conflict_target: {:unsafe_fragment, "(user_id, group_key) WHERE read_at IS NULL"}
          ]
      )
    end)

    broadcast(tenant, Enum.map(rows, & &1.user_id))
    for row <- rows, row.email_pending, do: row.user_id
  end

  ## Lectura (RF-NOT-001)

  @doc "Cuántas notificaciones sin leer tiene la persona."
  def unread_count(%Scope{user: %{id: user_id}} = scope) do
    from(n in Notification, where: n.user_id == ^user_id and is_nil(n.read_at), select: count())
    |> Repo.one(Tenancy.opts(scope))
  end

  def unread_count(_scope), do: 0

  @doc """
  Notificaciones de la persona, de la más reciente a la más vieja, con
  curso y autor. Filtros: `"course"`, `"event"` y `"unread"` (`"true"`);
  `"page"` desde 1.
  """
  def list(%Scope{user: %{id: user_id}} = scope, filters \\ %{}) do
    page = max(String.to_integer(to_string(filters["page"] || "1")), 1)

    from(n in Notification,
      where: n.user_id == ^user_id,
      order_by: [desc: n.updated_at, desc: n.id],
      limit: ^(@page + 1),
      offset: ^((page - 1) * @page),
      preload: [:actor, course: :pathway]
    )
    |> filter(:course, filters["course"])
    |> filter(:event, filters["event"])
    |> filter(:unread, filters["unread"])
    |> Repo.all(Tenancy.opts(scope))
    |> then(fn entries ->
      %{entries: Enum.take(entries, @page), page: page, more: length(entries) > @page}
    end)
  end

  defp filter(query, :course, id) when is_binary(id) and id != "" do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> where(query, [n], n.course_id == ^id)
      :error -> query
    end
  end

  defp filter(query, :event, event) when is_binary(event) and event != "",
    do: where(query, [n], n.event == ^event)

  defp filter(query, :unread, "true"), do: where(query, [n], is_nil(n.read_at))
  defp filter(query, _key, _value), do: query

  @doc "Cursos de las notificaciones de la persona (para filtrar)."
  def courses(%Scope{user: %{id: user_id}} = scope) do
    from(n in Notification,
      join: c in assoc(n, :course),
      where: n.user_id == ^user_id,
      distinct: true,
      order_by: c.name,
      select: c
    )
    |> Repo.all(Tenancy.opts(scope))
  end

  @doc "Marca una notificación como leída (y la devuelve), si es de la persona."
  def mark_read(%Scope{user: %{id: user_id}} = scope, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Notification{} = notification <-
           Repo.get_by(Notification, [id: id, user_id: user_id], Tenancy.opts(scope)) do
      notification =
        if notification.read_at,
          do: notification,
          else:
            notification
            |> Ecto.Changeset.change(read_at: DateTime.utc_now())
            |> Repo.update!(Tenancy.opts(scope))

      broadcast(scope, [user_id])
      {:ok, notification}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Marca como leídas todas las de la persona (con los mismos filtros de `list/2`)."
  def mark_all_read(%Scope{user: %{id: user_id}} = scope, filters \\ %{}) do
    {count, _} =
      from(n in Notification, where: n.user_id == ^user_id and is_nil(n.read_at))
      |> filter(:course, filters["course"])
      |> filter(:event, filters["event"])
      |> Repo.update_all([set: [read_at: DateTime.utc_now()]], Tenancy.opts(scope))

    broadcast(scope, [user_id])
    {:ok, count}
  end

  @doc """
  Lo que sigue a una entrega: el email agrupado de quienes lo esperan
  (RF-EML-004). Ver `Amauta.Notifications.EmailDigestWorker`.
  """
  def after_deliver(user_ids, tenant) do
    Enum.each(user_ids, &Amauta.Notifications.EmailDigestWorker.schedule(tenant, &1))
  end
end
