defmodule Amauta.Mail.RateLimit do
  @moduledoc """
  Límite de tasa del correo de la instancia (RF-EML-002, parcial: los
  límites por institución llegan en V1): cuántos emails por segundo,
  minuto, hora y día acepta el servidor SMTP.

      config :amauta, Amauta.Mail, rate_limits: [second: 5, minute: 120, hour: 2000, day: 20000]

  Un límite en `nil` no aplica. Cuenta en ventanas fijas, en memoria de
  este nodo (una tabla ETS).
  """
  use GenServer

  @table :amauta_mail_rate
  @windows [second: 1, minute: 60, hour: 3600, day: 86_400]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Pide lugar para un email. `:ok` (y lo cuenta) o `{:wait, segundos}` hasta
  que se libere la ventana llena.
  """
  def acquire(now \\ System.system_time(:second)) do
    limits = limits()

    full =
      Enum.find_value(@windows, fn {name, size} ->
        limit = limits[name]
        bucket = div(now, size)

        if limit && count({name, bucket}) >= limit,
          do: (bucket + 1) * size - now
      end)

    if full do
      {:wait, max(full, 1)}
    else
      for {name, size} <- @windows, limits[name] do
        :ets.update_counter(@table, {name, div(now, size)}, 1, {{name, div(now, size)}, 0})
      end

      :ok
    end
  end

  @doc "Límites configurados."
  def limits,
    do: Application.get_env(:amauta, Amauta.Mail, []) |> Keyword.get(:rate_limits, [])

  @doc "Cuánto tardaría en salir una cantidad de emails, en segundos (para envíos masivos)."
  def estimate(count) do
    limits = limits()

    @windows
    |> Enum.flat_map(fn {name, size} ->
      if limit = limits[name], do: [div(count, limit) * size], else: []
    end)
    |> Enum.max(fn -> 0 end)
  end

  defp count(key) do
    case :ets.lookup(@table, key) do
      [{^key, n}] -> n
      [] -> 0
    end
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_cleanup()
    {:ok, nil}
  end

  # Borra las ventanas que ya pasaron.
  @impl true
  def handle_info(:cleanup, state) do
    now = System.system_time(:second)

    for {name, size} <- @windows do
      :ets.select_delete(@table, [{{{name, :"$1"}, :_}, [{:<, :"$1", div(now, size)}], [true]}])
    end

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup, do: Process.send_after(self(), :cleanup, 60_000)
end
