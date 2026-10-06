defmodule Amauta.JobsTest do
  @moduledoc "Trabajos en segundo plano y efectos transaccionales de las acciones."
  use Amauta.DataCase, async: true
  use Oban.Testing, repo: Amauta.Repo, prefix: "global"

  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Actions, Audit}
  alias Amauta.Audit.{VerifyAllWorker, VerifyWorker}

  defmodule Notify do
    @moduledoc false
    use Amauta.Worker, queue: :notifications

    @impl Amauta.Worker
    def perform_for(_institution, _args), do: :ok
  end

  defmodule ActionWithEffects do
    @moduledoc false
    use Amauta.Action,
      name: "test.effect.create",
      description: "Acción de prueba con un efecto.",
      params: [fail: :boolean]

    @impl true
    def authorize(_scope, _input), do: :ok

    @impl true
    def run(_scope, %{fail: true}), do: {:error, :boom}
    def run(_scope, _input), do: {:ok, :done}

    @impl true
    def effects(scope, _input, _result), do: [Notify.new_for(scope, %{"kind" => "hello"})]
  end

  test "los efectos se encolan con la institución del scope" do
    scope = member_scope("teacher")
    assert {:ok, :done} = Actions.run(ActionWithEffects, scope, %{})

    assert_enqueued(
      worker: Notify,
      queue: :notifications,
      args: %{"kind" => "hello", "institution_id" => institution().id}
    )
  end

  test "si la acción falla, no se encola nada" do
    assert {:error, :boom} =
             Actions.run(ActionWithEffects, member_scope("teacher"), %{fail: true})

    refute_enqueued(worker: Notify)
  end

  test "el trabajo recibe la institución resuelta" do
    assert :ok = perform_job(Notify, %{"institution_id" => institution().id})

    assert {:cancel, :institution_not_found} =
             perform_job(Notify, %{"institution_id" => Ecto.UUID.generate()})
  end

  test "la verificación periódica encola un trabajo por institución" do
    institution()
    assert :ok = perform_job(VerifyAllWorker, %{})
    assert_enqueued(worker: VerifyWorker, args: %{"institution_id" => institution().id})
  end

  test "la verificación de una institución pasa con una cadena sana" do
    Audit.record!(institution(), "test.event")
    assert :ok = perform_job(VerifyWorker, %{"institution_id" => institution().id})
  end
end
