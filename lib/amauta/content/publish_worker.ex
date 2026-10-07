defmodule Amauta.Content.PublishWorker do
  @moduledoc """
  Publicación programada (RF-CON-005): a la hora de `publish_at`, crea las
  tarjetas del tablón de lo que el estudiantado empieza a ver. La
  visibilidad en sí no cambia acá (lo programado se ve solo cuando llega su
  fecha); este trabajo hace lo que tiene que pasar en ese momento.

  Si la unidad o el elemento cambiaron (otra fecha, oculto, borrado), el
  trabajo no hace nada que no corresponda: `Amauta.Content.sync_announcement/2`
  mira el estado actual.
  """
  use Amauta.Worker, queue: :deadlines, max_attempts: 5

  alias Amauta.{Content, Repo, Tenancy}
  alias Amauta.Content.Unit

  @impl Amauta.Worker
  def perform_for(institution, %{"item_id" => id}) do
    institution |> Content.sync_announcement(id) |> Content.broadcast_announcement()
    :ok
  end

  def perform_for(institution, %{"unit_id" => id}) do
    case Repo.get(Unit, id, Tenancy.opts(institution)) do
      nil ->
        {:cancel, :unit_not_found}

      unit ->
        for item_id <- Content.item_ids(institution, unit) do
          institution |> Content.sync_announcement(item_id) |> Content.broadcast_announcement()
        end

        :ok
    end
  end
end
