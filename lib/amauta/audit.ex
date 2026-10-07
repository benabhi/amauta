defmodule Amauta.Audit do
  @moduledoc """
  Auditoría por institución (sección 5.25 del ERS). Las acciones del dominio
  registran sus eventos en la misma transacción que el cambio.

  La auditoría es inmutable por dos vías:

    * la base rechaza `UPDATE` y `DELETE` (trigger `audit_events_immutable`);
    * cada evento lleva un número de secuencia, el hash del anterior y el
      suyo (encadenamiento, ERS 8.10). `verify_chain/1` recalcula la cadena
      y detecta cualquier alteración hecha por fuera de la aplicación.
  """
  import Ecto.Query

  alias Amauta.Audit.Event
  alias Amauta.{Repo, Tenancy}

  @genesis :binary.copy(<<0>>, 32)

  @doc """
  Registra un evento. `subject` es el struct afectado (se guardan su tipo y
  su ID) o `nil`.
  """
  @spec record!(Tenancy.tenant(), String.t(), keyword()) :: Event.t()
  def record!(tenant, action, opts \\ []) do
    subject = Keyword.get(opts, :subject)
    prefix = Tenancy.prefix(tenant)

    attrs = %{
      actor_id: Keyword.get(opts, :actor_id),
      action: action,
      subject_type: subject && subject_type(subject),
      subject_id: subject && subject.id,
      # Ida y vuelta por JSON: así el hash se calcula sobre lo mismo que
      # después se lee de la base (claves como texto).
      metadata: opts |> Keyword.get(:metadata, %{}) |> Jason.encode!() |> Jason.decode!()
    }

    {:ok, event} =
      Repo.transact(fn ->
        # Serializa los registros de la institución para que la cadena no se
        # bifurque con escrituras concurrentes.
        Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["audit:" <> prefix])
        {sequence, prev_hash} = last_link(tenant)

        event =
          %Event{}
          |> Event.changeset(attrs)
          |> Ecto.Changeset.put_change(:sequence, sequence + 1)
          |> Ecto.Changeset.put_change(:prev_hash, prev_hash)
          |> Ecto.Changeset.put_change(:inserted_at, DateTime.utc_now())
          |> Ecto.Changeset.apply_action!(:insert)

        {:ok, Repo.insert!(%{event | hash: hash(event)}, Tenancy.opts(tenant))}
      end)

    event
  end

  @doc "Eventos de la institución, del más antiguo al más reciente."
  def list_events(tenant, opts \\ []) do
    from(e in Event, order_by: [asc: e.sequence], limit: ^Keyword.get(opts, :limit, 100))
    |> Repo.all(Tenancy.opts(tenant))
  end

  @doc """
  Recalcula la cadena completa. `{:error, {:broken_at, secuencia}}` indica
  el primer evento alterado, faltante o fuera de orden.
  """
  @spec verify_chain(Tenancy.tenant()) :: :ok | {:error, {:broken_at, integer()}}
  def verify_chain(tenant) do
    {:ok, result} =
      Repo.transact(fn ->
        from(e in Event, order_by: [asc: e.sequence])
        |> Repo.stream(Tenancy.opts(tenant))
        |> Enum.reduce_while({0, @genesis}, fn event, {sequence, prev_hash} ->
          if event.sequence == sequence + 1 and event.prev_hash == prev_hash and
               event.hash == hash(event) do
            {:cont, {event.sequence, event.hash}}
          else
            {:halt, {:error, {:broken_at, event.sequence}}}
          end
        end)
        |> then(fn
          {:error, _} = error -> {:ok, error}
          _ -> {:ok, :ok}
        end)
      end)

    result
  end

  defp last_link(tenant) do
    from(e in Event, order_by: [desc: e.sequence], limit: 1, select: {e.sequence, e.hash})
    |> Repo.one(Tenancy.opts(tenant))
    |> Kernel.||({0, @genesis})
  end

  @doc false
  def hash(%Event{} = event) do
    canonical =
      Jason.encode!([
        event.sequence,
        Base.encode16(event.prev_hash),
        event.actor_id,
        event.action,
        event.subject_type,
        event.subject_id,
        canonical_json(event.metadata),
        event.inserted_at |> DateTime.truncate(:microsecond) |> DateTime.to_iso8601()
      ])

    :crypto.hash(:sha256, canonical)
  end

  # Los mapas se ordenan por clave: jsonb no conserva el orden.
  defp canonical_json(map) when is_map(map),
    do: map |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(fn {k, v} -> [k, canonical_json(v)] end)

  defp canonical_json(list) when is_list(list), do: Enum.map(list, &canonical_json/1)
  defp canonical_json(value), do: value

  defp subject_type(%module{}), do: module |> Module.split() |> List.last()
end
