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

  describe "cadena de hashes" do
    test "cada evento enlaza con el anterior y la cadena verifica", %{institution: i} do
      first = Audit.record!(i, "test.first", metadata: %{b: 2, a: %{z: 1, y: [1, 2]}})
      second = Audit.record!(i, "test.second")

      assert first.sequence == 1
      assert second.sequence == 2
      assert second.prev_hash == first.hash
      assert byte_size(first.hash) == 32
      assert :ok = Audit.verify_chain(i)
    end

    test "una cadena vacía es válida", %{institution: i} do
      assert :ok = Audit.verify_chain(i)
    end

    test "detecta un evento alterado por fuera de la aplicación", %{institution: i} do
      Audit.record!(i, "test.first")
      tampered = Audit.record!(i, "test.second", metadata: %{"grade" => 4})
      Audit.record!(i, "test.third")

      # Simula una edición directa en la base, saltando el trigger.
      prefix = Tenancy.prefix(i)
      Repo.query!(~s(ALTER TABLE "#{prefix}".audit_events DISABLE TRIGGER audit_events_immutable))

      Repo.query!(
        ~s(UPDATE "#{prefix}".audit_events SET metadata = '{"grade": 10}' WHERE id = $1),
        [Ecto.UUID.dump!(tampered.id)]
      )

      assert {:error, {:broken_at, 2}} = Audit.verify_chain(i)
    end

    test "detecta un evento borrado", %{institution: i} do
      Audit.record!(i, "test.first")
      deleted = Audit.record!(i, "test.second")
      Audit.record!(i, "test.third")

      prefix = Tenancy.prefix(i)
      Repo.query!(~s(ALTER TABLE "#{prefix}".audit_events DISABLE TRIGGER audit_events_immutable))

      Repo.query!(~s(DELETE FROM "#{prefix}".audit_events WHERE id = $1), [
        Ecto.UUID.dump!(deleted.id)
      ])

      assert {:error, {:broken_at, 3}} = Audit.verify_chain(i)
    end
  end
end
