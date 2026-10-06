defmodule Amauta.PlatformTest do
  use Amauta.DataCase, async: true

  import Amauta.Fixtures
  alias Amauta.Platform
  alias Amauta.Platform.Institution

  describe "validaciones de la institución" do
    defp errors(attrs), do: %Institution{} |> Institution.changeset(attrs) |> errors_on()

    test "slug: minúsculas, números y guiones, sin guion al principio ni al final" do
      assert errors(%{slug: "unsur", name: "X"}) == %{}
      assert errors(%{slug: "UNSur", name: "X"}) == %{}
      assert %{slug: [_]} = errors(%{slug: "-unsur", name: "X"})
      assert %{slug: [_]} = errors(%{slug: "un_sur", name: "X"})
      assert %{slug: [_]} = errors(%{slug: "a", name: "X"})
    end

    test "slug: rechaza los reservados por las rutas" do
      for slug <- Institution.reserved_slugs() do
        assert %{slug: ["is reserved"]} = errors(%{slug: slug, name: "X"})
      end
    end

    test "zona horaria: debe existir en la base IANA" do
      assert errors(%{slug: "x1", name: "X", timezone: "America/Argentina/Cordoba"}) == %{}
      assert %{timezone: [_]} = errors(%{slug: "x1", name: "X", timezone: "Marte/Olympus"})
    end
  end

  test "busca por slug" do
    institution = institution_fixture()
    assert Platform.get_institution_by_slug(institution.slug).id == institution.id
    assert Platform.get_institution_by_slug("no-existe") == nil
  end

  test "suspende y reactiva" do
    institution = institution_fixture()
    assert {:ok, %{status: "suspended"} = institution} = Platform.suspend_institution(institution)
    assert {:ok, %{status: "active"}} = Platform.activate_institution(institution)
  end

  test "el schema no cambia al editar el slug" do
    institution = institution_fixture()
    {:ok, updated} = Platform.update_institution(institution, %{slug: "nuevo-slug"})
    assert updated.schema_name == institution.schema_name
  end
end
