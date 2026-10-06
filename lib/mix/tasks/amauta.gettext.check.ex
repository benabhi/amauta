defmodule Mix.Tasks.Amauta.Gettext.Check do
  @shortdoc "Verifica que la traducción al español esté completa"
  @moduledoc """
  Falla si algún mensaje del español no tiene traducción o quedó marcado
  como dudoso (`fuzzy`). El español es el idioma por defecto, así que su
  traducción es obligatoria y completa (ERS 9.4).

      mix amauta.gettext.check
  """
  use Mix.Task

  @locale "es"

  @impl true
  def run(_args) do
    problems =
      "priv/gettext/#{@locale}/LC_MESSAGES/*.po"
      |> Path.wildcard()
      |> Enum.flat_map(&problems/1)

    if problems == [] do
      Mix.shell().info("Traducción al español completa.")
    else
      for {file, message, reason} <- problems do
        Mix.shell().error("#{file}: #{reason}: #{inspect(message)}")
      end

      Mix.raise("#{length(problems)} message(s) without a valid Spanish translation")
    end
  end

  defp problems(file) do
    file
    |> Expo.PO.parse_file!()
    |> Map.fetch!(:messages)
    |> Enum.flat_map(fn message ->
      cond do
        Expo.Message.has_flag?(message, "fuzzy") -> [{file, msgid(message), "fuzzy"}]
        untranslated?(message) -> [{file, msgid(message), "untranslated"}]
        true -> []
      end
    end)
  end

  defp untranslated?(%Expo.Message.Singular{msgstr: msgstr}), do: blank?(msgstr)

  defp untranslated?(%Expo.Message.Plural{msgstr: msgstr}),
    do: msgstr == %{} or Enum.any?(Map.values(msgstr), &blank?/1)

  defp blank?(parts), do: parts |> IO.iodata_to_binary() |> String.trim() == ""

  defp msgid(message), do: message.msgid |> IO.iodata_to_binary()
end
