defmodule AmautaWeb.DevCodeReloader.Watcher do
  @moduledoc """
  Solo en desarrollo: anota si cambió el código desde la última
  recompilación, escuchando al vigilante de archivos de
  `phoenix_live_reload` (`:phoenix_live_reload_file_monitor`).

  Si ese vigilante no está, queda siempre «con cambios» y se recompila en
  cada pedido, como sin este módulo.
  """
  use GenServer

  @monitor :phoenix_live_reload_file_monitor
  @extensions ~w(.ex .exs .heex .po .pot)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Si hubo cambios desde la última vez que se preguntó (y los da por vistos)."
  def take_changes do
    GenServer.call(__MODULE__, :take_changes)
  catch
    :exit, _ -> true
  end

  @impl true
  def init(_opts) do
    # FileSystem es dependencia solo de desarrollo: se llama sin referencia
    # directa para que compile en los demás entornos.
    subscribed =
      Process.whereis(@monitor) != nil and
        apply(FileSystem, :subscribe, [@monitor]) == :ok

    # Al arrancar se recompila una vez, por si algo cambió con la app parada.
    {:ok, %{changed: true, subscribed: subscribed}}
  end

  @impl true
  def handle_call(:take_changes, _from, state) do
    {:reply, state.changed, %{state | changed: not state.subscribed}}
  end

  @impl true
  def handle_info({:file_event, _pid, {path, _events}}, state) do
    changed = state.changed or Path.extname(path) in @extensions
    {:noreply, %{state | changed: changed}}
  end

  def handle_info({:file_event, _pid, :stop}, state),
    do: {:noreply, %{state | changed: true, subscribed: false}}

  def handle_info(_message, state), do: {:noreply, state}
end
