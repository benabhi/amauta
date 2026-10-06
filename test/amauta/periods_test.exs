defmodule Amauta.PeriodsTest do
  @moduledoc "Períodos lectivos (RF-INS-009)."
  use Amauta.DataCase, async: true

  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Actions, Audit, Periods}
  alias Amauta.Periods.AcademicPeriod
  alias Amauta.Periods.Actions.{CreatePeriod, SetCurrentPeriod, UpdatePeriod}

  defp period_params(attrs \\ %{}) do
    Enum.into(attrs, %{
      "name" => "2027 · 1.er cuatrimestre",
      "starts_on" => "2027-03-01",
      "ends_on" => "2027-07-15"
    })
  end

  setup do
    %{admin: member_scope("institution_admin")}
  end

  test "crea un período y queda auditado", %{admin: admin} do
    assert {:ok, %AcademicPeriod{current: false} = period} =
             Actions.run(CreatePeriod, admin, period_params())

    assert period.starts_on == ~D[2027-03-01]
    assert [%{action: "periods.period.create"}] = Audit.list_events(admin)
  end

  test "valida nombre único y fechas ordenadas", %{admin: admin} do
    {:ok, _} = Actions.run(CreatePeriod, admin, period_params())

    assert {:error, changeset} =
             Actions.run(
               CreatePeriod,
               admin,
               period_params(%{"name" => "2027 · 1.ER CUATRIMESTRE"})
             )

    assert %{name: ["already exists"]} = errors_on(changeset)

    assert {:error, changeset} =
             Actions.run(
               CreatePeriod,
               admin,
               period_params(%{"name" => "Otro", "ends_on" => "2027-01-01"})
             )

    assert %{ends_on: ["must be after the start"]} = errors_on(changeset)
  end

  test "solo hay un período actual", %{admin: admin} do
    {:ok, first} = Actions.run(CreatePeriod, admin, period_params(%{"current" => "true"}))
    assert first.current

    {:ok, second} =
      Actions.run(
        CreatePeriod,
        admin,
        period_params(%{
          "name" => "2027 · 2.º cuatrimestre",
          "starts_on" => "2027-08-01",
          "ends_on" => "2027-12-15"
        })
      )

    assert Periods.current(admin).id == first.id

    {:ok, _} = Actions.run(SetCurrentPeriod, admin, %{"period_id" => second.id})
    assert Periods.current(admin).id == second.id
    refute Periods.get(admin, first.id).current
  end

  test "edita un período", %{admin: admin} do
    {:ok, period} = Actions.run(CreatePeriod, admin, period_params())

    assert {:ok, %{name: "2027 · Primer cuatrimestre"}} =
             Actions.run(UpdatePeriod, admin, %{
               "period_id" => period.id,
               "name" => "2027 · Primer cuatrimestre"
             })

    assert {:error, :not_found} =
             Actions.run(UpdatePeriod, admin, %{"period_id" => Ecto.UUID.generate()})
  end

  describe "matriz rol × acción" do
    for {role, allowed} <- [
          {"institution_admin", true},
          {"academic_management", true},
          {"pathway_coordinator", false},
          {"teacher", false},
          {"student", false},
          {"observer", false}
        ] do
      test "#{role} #{if allowed, do: "puede", else: "no puede"} gestionar períodos" do
        scope = member_scope(unquote(role))
        result = Actions.run(CreatePeriod, scope, period_params())

        if unquote(allowed),
          do: assert({:ok, _} = result),
          else: assert({:error, :forbidden} = result)
      end
    end
  end

  test "los períodos de una institución no se ven desde otra" do
    a = institution()
    b = Amauta.Fixtures.institution_fixture("inst_test_b")

    {:ok, _} = Periods.create(a, period_params())

    assert [_] = Periods.list(a)
    assert [] = Periods.list(b)
  end
end
