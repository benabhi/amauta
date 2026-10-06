defmodule Amauta.AuditTest do
  use Amauta.DataCase, async: true

  import Amauta.Fixtures
  alias Amauta.Audit
  alias Amauta.Tenancy

  setup do
    %{institution: institution_fixture()}
  end

  test "registra actor, acción, sujeto y metadatos", %{institution: i} do
    actor_id = Ecto.UUID.generate()

    event =
      Audit.record!(i, "platform.institution.update",
        actor_id: actor_id,
        subject: i,
        metadata: %{"field" => "name"}
      )

    assert event.actor_id == actor_id
    assert event.subject_type == "Institution"
    assert event.subject_id == i.id
    assert [%{metadata: %{"field" => "name"}}] = Audit.list_events(i)
  end

  test "valida el formato del nombre de la acción", %{institution: i} do
    assert_raise Ecto.InvalidChangesetError, fn -> Audit.record!(i, "Sin Formato") end
  end

  test "los eventos son inmutables en la base", %{institution: i} do
    event = Audit.record!(i, "test.immutable")

    assert_raise Postgrex.Error, ~r/audit events are immutable/, fn ->
      event |> Ecto.Changeset.change(action: "test.changed") |> Repo.update!(Tenancy.opts(i))
    end
  end

  test "los eventos no se pueden borrar", %{institution: i} do
    event = Audit.record!(i, "test.immutable")

    assert_raise Postgrex.Error, ~r/audit events are immutable/, fn ->
      Repo.delete!(event, Tenancy.opts(i))
    end
  end
end
