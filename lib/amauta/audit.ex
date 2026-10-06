defmodule Amauta.Audit do
  @moduledoc """
  Auditoría por institución (sección 5.25 del ERS). Las acciones del dominio
  registran sus eventos en la misma transacción que el cambio.
  """
  import Ecto.Query
  alias Amauta.Audit.Event
  alias Amauta.{Repo, Tenancy}

  @doc """
  Registra un evento. `subject` es el struct afectado (se guardan su tipo y
  su ID) o `nil`.
  """
  @spec record!(Tenancy.tenant(), String.t(), keyword()) :: Event.t()
  def record!(tenant, action, opts \\ []) do
    subject = Keyword.get(opts, :subject)

    %Event{}
    |> Event.changeset(%{
      actor_id: Keyword.get(opts, :actor_id),
      action: action,
      subject_type: subject && subject_type(subject),
      subject_id: subject && subject.id,
      metadata: Keyword.get(opts, :metadata, %{})
    })
    |> Repo.insert!(Tenancy.opts(tenant))
  end

  @doc "Eventos de la institución, del más antiguo al más reciente."
  def list_events(tenant, opts \\ []) do
    from(e in Event,
      order_by: [asc: e.inserted_at, asc: e.id],
      limit: ^Keyword.get(opts, :limit, 100)
    )
    |> Repo.all(Tenancy.opts(tenant))
  end

  defp subject_type(%module{}), do: module |> Module.split() |> List.last()
end
