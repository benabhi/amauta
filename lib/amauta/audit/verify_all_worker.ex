defmodule Amauta.Audit.VerifyAllWorker do
  @moduledoc """
  Trabajo periódico (Oban.Plugins.Cron): encola la verificación de la
  auditoría de cada institución.
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  alias Amauta.Audit.VerifyWorker

  @impl Oban.Worker
  def perform(_job) do
    Amauta.Platform.list_institutions()
    |> Enum.map(&VerifyWorker.new_for/1)
    |> Oban.insert_all()

    :ok
  end
end
