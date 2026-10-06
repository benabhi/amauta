defmodule Amauta.Accounts.LoginThrottle do
  @moduledoc """
  Defensa contra fuerza bruta y relleno de credenciales (RF-AUT-006,
  RNF-SEG-012 y RNF-SEG-018).

  Cuenta los intentos fallidos por cuenta (institución + email) y por IP
  dentro de una ventana. Al pasar el umbral, bloquea por un tiempo que se
  duplica con cada bloqueo nuevo, hasta un máximo. Un inicio de sesión
  correcto limpia el contador de la cuenta.

  Vive en ETS, en cada nodo: con un clúster, un atacante podría repartir los
  intentos entre nodos; se resuelve cuando haya clúster (ERS 8.11).
  """
  use GenServer

  @table :amauta_login_throttle
  @window_ms :timer.minutes(15)
  @max_lock_ms :timer.minutes(30)

  @limits %{
    account: %{failures: 5, base_lock_ms: :timer.minutes(1)},
    ip: %{failures: 20, base_lock_ms: :timer.minutes(5)},
    magic_link: %{failures: 3, base_lock_ms: :timer.minutes(15)}
  }

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    :timer.send_interval(:timer.minutes(5), :sweep)
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = now()
    # Borra las entradas sin bloqueo vigente y con la ventana vencida.
    :ets.select_delete(@table, [
      {{:_, :_, :"$1", :_, :"$2"}, [{:<, {:+, :"$1", @window_ms}, now}, {:<, :"$2", now}], [true]}
    ])

    {:noreply, state}
  end

  @doc """
  `:ok` si se puede intentar; `{:error, {:locked, segundos}}` si la cuenta
  o la IP están bloqueadas.
  """
  @spec check(Ecto.UUID.t(), :inet.ip_address(), String.t()) ::
          :ok | {:error, {:locked, pos_integer()}}
  def check(institution_id, ip, email) do
    if enabled?(), do: do_check(institution_id, ip, email), else: :ok
  end

  defp do_check(institution_id, ip, email) do
    [account_key(institution_id, email), ip_key(ip)]
    |> Enum.map(&locked_for/1)
    |> Enum.max()
    |> case do
      0 -> :ok
      ms -> {:error, {:locked, div(ms + 999, 1000)}}
    end
  end

  @doc """
  Registra un intento fallido. Devuelve `:locked` si este intento bloqueó
  la cuenta (para avisarle a la persona), o `:ok`.
  """
  @spec record_failure(Ecto.UUID.t(), :inet.ip_address(), String.t()) :: :ok | :locked
  def record_failure(institution_id, ip, email) do
    if enabled?(), do: do_record_failure(institution_id, ip, email), else: :ok
  end

  defp do_record_failure(institution_id, ip, email) do
    hit(ip_key(ip), :ip)
    hit(account_key(institution_id, email), :account)
  end

  @doc "Limpia el contador de la cuenta tras un inicio de sesión correcto."
  def record_success(institution_id, email) do
    :ets.delete(@table, account_key(institution_id, email))
    :ok
  end

  @doc """
  Límite de envíos de enlaces mágicos por cuenta: `true` si se puede enviar
  otro. Evita usar la plataforma para inundar un buzón.
  """
  @spec allow_magic_link?(Ecto.UUID.t(), String.t()) :: boolean()
  def allow_magic_link?(institution_id, email) do
    if enabled?(), do: do_allow_magic_link?(institution_id, email), else: true
  end

  defp do_allow_magic_link?(institution_id, email) do
    key = {:magic_link, institution_id, normalize(email)}

    if locked_for(key) > 0 do
      false
    else
      hit(key, :magic_link)
      true
    end
  end

  @doc false
  def reset, do: :ets.delete_all_objects(@table)

  # En los tests está apagado: todos salen de la misma IP y se bloquearían
  # entre sí. Los tests del limitador lo encienden.
  defp enabled?, do: Application.get_env(:amauta, __MODULE__, [])[:enabled] != false

  # {clave, fallos, inicio de la ventana, bloqueos acumulados, bloqueado hasta}
  defp hit(key, kind) do
    %{failures: max, base_lock_ms: base} = Map.fetch!(@limits, kind)
    now = now()

    {failures, window_start, locks, _until} =
      case :ets.lookup(@table, key) do
        [{^key, f, start, l, u}] when start + @window_ms > now -> {f, start, l, u}
        [{^key, _f, _start, l, u}] -> {0, now, l, u}
        [] -> {0, now, 0, 0}
      end

    failures = failures + 1

    if failures >= max do
      lock_ms = min(base * Integer.pow(2, locks), @max_lock_ms)
      :ets.insert(@table, {key, 0, now, locks + 1, now + lock_ms})
      :locked
    else
      :ets.insert(@table, {key, failures, window_start, locks, 0})
      :ok
    end
  end

  defp locked_for(key) do
    case :ets.lookup(@table, key) do
      [{^key, _f, _start, _locks, until}] -> max(until - now(), 0)
      [] -> 0
    end
  end

  defp account_key(institution_id, email), do: {:account, institution_id, normalize(email)}
  defp ip_key(ip), do: {:ip, ip}
  defp normalize(email), do: email |> String.trim() |> String.downcase()
  # Hora del sistema: el tiempo monotónico puede ser negativo, y 0 significa
  # «sin bloqueo».
  defp now, do: System.system_time(:millisecond)
end
