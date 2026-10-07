defmodule Amauta.Audit.VerifyWorker do
  @moduledoc """
  Verifica la cadena de hashes de la auditoría de una institución. Si está
  rota, lo registra como error (las alertas llegan con la consola de
  errores, H4) y el trabajo falla para que quede a la vista en Oban.
  """
  use Amauta.Worker, queue: :maintenance, max_attempts: 1

  require Logger

  @impl Amauta.Worker
  def perform_for(institution, _args) do
    case Amauta.Audit.verify_chain(institution) do
      :ok ->
        :ok

      {:error, {:broken_at, sequence}} = error ->
        Logger.error("audit chain broken for #{institution.slug} at sequence #{sequence}")
        error
    end
  end
end
