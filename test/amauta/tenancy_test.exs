defmodule Amauta.TenancyTest do
  @moduledoc "Aislamiento entre instituciones (RNF-SEG-002)."
  use Amauta.DataCase, async: true

  import Amauta.Fixtures
  alias Amauta.{Audit, Tenancy}
  alias Amauta.Audit.Event

  setup do
    %{a: institution_fixture("inst_test_a"), b: institution_fixture("inst_test_b")}
  end

  describe "guardia del Repo" do
    test "rechaza consultas sin prefijo" do
      assert_raise Tenancy.MissingPrefixError, fn -> Repo.all(Event) end
      assert_raise Tenancy.MissingPrefixError, fn -> Repo.get(Event, Ecto.UUID.generate()) end
      assert_raise Tenancy.MissingPrefixError, fn -> Repo.aggregate(Event, :count) end
    end

    test "rechaza joins sin prefijo aunque el from lo tenga", %{a: a} do
      query =
        from(e in Event, prefix: ^Tenancy.prefix(a), join: o in Event, on: o.id == e.id)

      assert_raise Tenancy.MissingPrefixError, fn -> Repo.all(query) end
    end

    test "acepta el prefijo por opción, en la consulta o en el schema", %{a: a} do
      assert [] = Repo.all(Event, Tenancy.opts(a))
      assert [] = Repo.all(from(e in Event, prefix: ^Tenancy.prefix(a)))
      assert is_list(Repo.all(Amauta.Platform.Institution))
    end

    test "una escritura sin prefijo falla en la base" do
      assert_raise Postgrex.Error, ~r/relation "audit_events" does not exist/, fn ->
        Repo.insert!(%Event{action: "test.write"})
      end
    end
  end

  test "los datos de una institución no se ven desde otra", %{a: a, b: b} do
    Audit.record!(a, "test.only_a")

    assert [%Event{action: "test.only_a"}] = Audit.list_events(a)
    assert [] = Audit.list_events(b)
  end

  test "prefix/1 acepta la institución o un mapa con ella", %{a: a} do
    assert Tenancy.prefix(a) == "inst_test_a"
    assert Tenancy.prefix(%{institution: a}) == "inst_test_a"
    assert Tenancy.opts(a) == [prefix: "inst_test_a"]
  end
end
