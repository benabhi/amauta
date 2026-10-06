NimbleCSV.define(Amauta.Accounts.Import.CommaParser, separator: ",", escape: "\"")
NimbleCSV.define(Amauta.Accounts.Import.SemicolonParser, separator: ";", escape: "\"")

defmodule Amauta.Accounts.Import do
  @moduledoc """
  Importación de personas desde CSV (RF-USR-004 y RF-IMP-006): lectura,
  mapeo de columnas, validación por fila y simulación. Aplicar el plan es
  la acción `Amauta.Accounts.Actions.ImportUsers`.

  Acepta coma o punto y coma como separador (Excel en español exporta con
  punto y coma) y UTF-8, con o sin BOM.
  """
  alias Amauta.Accounts
  alias Amauta.Accounts.User
  alias Amauta.Accounts.Import.{CommaParser, SemicolonParser}

  @max_rows 5_000

  @fields [:first_name, :last_name, :email, :preferred_name]

  # Encabezados que se reconocen para cada campo, ya normalizados.
  @synonyms %{
    first_name: ~w(first_name firstname nombre nombres name),
    last_name: ~w(last_name lastname surname apellido apellidos),
    email: ~w(email e-mail mail correo correo_electronico),
    preferred_name: ~w(preferred_name nombre_preferido apodo)
  }

  @type row :: %{
          line: pos_integer(),
          attrs: map(),
          status: :create | :exists | :error,
          errors: [{atom(), String.t()}]
        }

  @doc "Campos que se pueden mapear."
  def fields, do: @fields

  @doc "Lee un CSV: `{:ok, %{headers, rows}}` o `{:error, motivo}`."
  @spec parse(binary()) ::
          {:ok, %{headers: [String.t()], rows: [[String.t()]]}} | {:error, atom()}
  def parse(content) when is_binary(content) do
    content = strip_bom(content)

    cond do
      not String.valid?(content) ->
        {:error, :not_utf8}

      String.trim(content) == "" ->
        {:error, :empty}

      true ->
        parser = if semicolon?(content), do: SemicolonParser, else: CommaParser

        case parser.parse_string(content, skip_headers: false) do
          [headers | rows] ->
            rows = Enum.reject(rows, fn row -> Enum.all?(row, &(String.trim(&1) == "")) end)

            if length(rows) > @max_rows,
              do: {:error, :too_many_rows},
              else: {:ok, %{headers: Enum.map(headers, &String.trim/1), rows: rows}}

          [] ->
            {:error, :empty}
        end
    end
  rescue
    NimbleCSV.ParseError -> {:error, :invalid_csv}
  end

  @doc """
  Mapeo sugerido a partir de los encabezados: `%{campo => índice}`.
  """
  @spec guess_mapping([String.t()]) :: %{atom() => non_neg_integer()}
  def guess_mapping(headers) do
    normalized = headers |> Enum.map(&normalize_header/1) |> Enum.with_index()

    for field <- @fields,
        {_header, index} <- [Enum.find(normalized, fn {h, _} -> h in @synonyms[field] end)],
        into: %{},
        do: {field, index}
  end

  @doc """
  Plan de la importación: cada fila con sus datos, su estado y sus errores.
  No escribe nada (simulación, RF-USR-004).
  """
  @spec plan(Amauta.Tenancy.tenant(), [[String.t()]], map()) :: [row()]
  def plan(tenant, rows, mapping) do
    {planned, _seen} =
      rows
      |> Enum.with_index(2)
      |> Enum.map_reduce(MapSet.new(), fn {row, line}, seen ->
        attrs = extract(row, mapping)
        email = attrs |> Map.get(:email, "") |> String.downcase()

        {status, errors} =
          cond do
            (errors = validate(tenant, attrs)) != [] ->
              {:error, errors}

            MapSet.member?(seen, email) ->
              {:error, [{:email, translate("is duplicated in the file", [])}]}

            Accounts.get_user_by_email(tenant, email) ->
              {:exists, []}

            true ->
              {:create, []}
          end

        {%{line: line, attrs: attrs, status: status, errors: errors}, MapSet.put(seen, email)}
      end)

    planned
  end

  @doc "Totales del plan por estado."
  def summary(plan) do
    Map.merge(%{create: 0, exists: 0, error: 0}, Enum.frequencies_by(plan, & &1.status))
  end

  @doc """
  Reporte de errores en CSV (línea, email y errores), para descargar.
  `label` da el nombre visible de cada campo.
  """
  def error_report(plan, label \\ &Atom.to_string/1) do
    rows =
      for %{status: :error} = row <- plan do
        errors =
          Enum.map_join(row.errors, "; ", fn {field, message} ->
            "#{label.(field)}: #{message}"
          end)

        [Integer.to_string(row.line), Map.get(row.attrs, :email, ""), errors]
      end

    CommaParser.dump_to_iodata([["line", "email", "errors"] | rows]) |> IO.iodata_to_binary()
  end

  defp extract(row, mapping) do
    for {field, index} <- mapping, index != nil, into: %{} do
      {field, row |> Enum.at(index, "") |> String.trim()}
    end
  end

  defp validate(tenant, attrs) do
    changeset =
      tenant
      |> then(&Ecto.put_meta(%User{}, prefix: Amauta.Tenancy.prefix(&1)))
      |> User.create_changeset(attrs)
      |> Map.put(:action, :validate)

    # La unicidad del email se resuelve en el plan ("ya existe"), no como error.
    for {field, {message, opts}} <- changeset.errors,
        not (field == :email and opts[:validation] == :unsafe_unique) do
      {field, translate(message, opts)}
    end
  end

  # Mismo dominio de Gettext que los errores de los formularios.
  defp translate(message, opts) do
    if count = opts[:count] do
      Gettext.dngettext(AmautaWeb.Gettext, "errors", message, message, count, opts)
    else
      Gettext.dgettext(AmautaWeb.Gettext, "errors", message, opts)
    end
  end

  defp normalize_header(header) do
    header
    |> String.trim()
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/[\s.]+/, "_")
  end

  defp semicolon?(content) do
    first_line = content |> String.split(~r/\R/, parts: 2) |> hd()
    count(first_line, ";") > count(first_line, ",")
  end

  defp count(string, char), do: string |> String.graphemes() |> Enum.count(&(&1 == char))

  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(content), do: content
end
