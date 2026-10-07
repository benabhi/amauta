defmodule AmautaWeb.DevCodeReloader do
  @moduledoc """
  Solo en desarrollo: `Phoenix.CodeReloader`, pero únicamente cuando cambió
  el código (`AmautaWeb.DevCodeReloader.Watcher`).

  El recargador de Phoenix revisa todos los archivos fuente en cada pedido.
  Con la carpeta compartida desde Windows eso tardaba ~1,7 s por página
  aunque no hubiera nada que compilar.
  """
  @behaviour Plug

  alias AmautaWeb.DevCodeReloader.Watcher

  @impl true
  def init(opts), do: Phoenix.CodeReloader.init(opts)

  @impl true
  def call(conn, opts) do
    if Watcher.take_changes(), do: Phoenix.CodeReloader.call(conn, opts), else: conn
  end
end
