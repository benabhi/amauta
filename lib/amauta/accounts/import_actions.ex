defmodule Amauta.Accounts.Actions.ImportUsers do
  @moduledoc """
  Aplica una importación de personas ya simulada (RF-USR-004): crea las
  filas válidas nuevas, saltea las que ya existen y vuelve a validar cada
  una, por si algo cambió desde la simulación. Todo en una transacción.
  Deshacer la importación llega en V1.
  """
  use Amauta.Action,
    name: "accounts.user.import",
    description: "Importa personas desde un CSV ya validado.",
    params: [
      rows: {{:array, :map}, required: true},
      send_invitations: :boolean
    ]

  alias Amauta.Accounts
  alias Amauta.Accounts.Actions.Helpers

  @max_rows 5_000

  @impl true
  def validate(changeset) do
    Ecto.Changeset.validate_length(changeset, :rows, min: 1, max: @max_rows)
  end

  @impl true
  def authorize(scope, _input), do: Helpers.authorize_manage(scope)

  @impl true
  def run(scope, %{rows: rows}) do
    Enum.reduce_while(rows, {:ok, %{created: [], skipped: 0}}, fn row, {:ok, acc} ->
      attrs = Map.new(row, fn {k, v} -> {to_string(k), v} end)

      if Accounts.get_user_by_email(scope, attrs["email"] || "") do
        {:cont, {:ok, %{acc | skipped: acc.skipped + 1}}}
      else
        case Accounts.register_user(scope, attrs) do
          {:ok, user} -> {:cont, {:ok, %{acc | created: [user | acc.created]}}}
          {:error, changeset} -> {:halt, {:error, changeset}}
        end
      end
    end)
  end

  @impl true
  def audit(_scope, input, %{created: created, skipped: skipped}) do
    {nil,
     %{
       "created" => length(created),
       "skipped" => skipped,
       "send_invitations" => Map.get(input, :send_invitations, true)
     }}
  end

  @impl true
  def effects(scope, input, %{created: created}) do
    if Map.get(input, :send_invitations, true),
      do: Enum.map(created, &Helpers.invitation(scope, &1)),
      else: []
  end
end

defmodule Amauta.Accounts.Actions.ExportUsers do
  @moduledoc """
  Exporta el directorio filtrado a CSV (RF-IMP-005). Tiene datos personales,
  así que queda auditado con los filtros y la cantidad de filas.
  """
  use Amauta.Action,
    name: "accounts.user.export",
    description: "Exporta las personas a CSV, respetando los filtros.",
    params: [q: :string, status: :string, role: :string]

  alias Amauta.Accounts.Directory
  alias Amauta.Accounts.Import.CommaParser
  alias Amauta.Authorization

  @impl true
  def authorize(scope, _input), do: Authorization.authorize(scope, "institution.users.view")

  @impl true
  def run(scope, input) do
    users = Directory.all(scope, input)

    rows =
      for user <- users do
        [user.first_name, user.last_name, user.preferred_name || "", user.email, user.status]
      end

    csv =
      [["first_name", "last_name", "preferred_name", "email", "status"] | rows]
      |> CommaParser.dump_to_iodata()
      |> IO.iodata_to_binary()

    {:ok, %{csv: csv, count: length(users)}}
  end

  @impl true
  def audit(_scope, input, %{count: count}), do: {nil, Map.put(input, :count, count)}
end
