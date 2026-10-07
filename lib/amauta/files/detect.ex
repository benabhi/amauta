defmodule Amauta.Files.Detect do
  @moduledoc """
  Tipo real de un archivo a partir de sus primeros bytes (RF-ARC-004), no
  de lo que dice el navegador ni de la extensión.

  Para los formatos que comparten firma (los de oficina son ZIP u OLE, y
  el texto plano no tiene firma), la extensión decide entre los tipos
  compatibles con el contenido; nunca al revés.
  """

  @doc "Cuántos bytes hacen falta para reconocer el tipo."
  def head_size, do: 4096

  # Tipo esperado para cada extensión conocida.
  @by_extension %{
    "pdf" => "application/pdf",
    "png" => "image/png",
    "jpg" => "image/jpeg",
    "jpeg" => "image/jpeg",
    "gif" => "image/gif",
    "webp" => "image/webp",
    "mp4" => "video/mp4",
    "m4a" => "audio/mp4",
    "mp3" => "audio/mpeg",
    "zip" => "application/zip",
    "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    "odt" => "application/vnd.oasis.opendocument.text",
    "ods" => "application/vnd.oasis.opendocument.spreadsheet",
    "odp" => "application/vnd.oasis.opendocument.presentation",
    "doc" => "application/msword",
    "xls" => "application/vnd.ms-excel",
    "ppt" => "application/vnd.ms-powerpoint",
    "txt" => "text/plain",
    "csv" => "text/csv",
    "md" => "text/markdown"
  }

  @zip_family ~w(zip docx xlsx pptx odt ods odp)
  @ole_family ~w(doc xls ppt)
  @text_family ~w(txt csv md)

  @doc "Tipos que se reconocen."
  def known_types, do: @by_extension |> Map.values() |> Enum.uniq() |> Enum.sort()

  @doc "Tipo esperado por la extensión del nombre, o `nil` si no se conoce."
  def by_extension(filename), do: Map.get(@by_extension, extension(filename))

  @doc """
  Tipo real según el contenido y el nombre. Devuelve `{:ok, tipo}`,
  `{:error, :unknown}` si el contenido no es de un tipo conocido o
  `{:error, :mismatch}` si no coincide con la extensión.
  """
  @spec detect(binary(), String.t()) :: {:ok, String.t()} | {:error, :unknown | :mismatch}
  def detect(head, filename) when is_binary(head) do
    ext = extension(filename)

    case {signature(head), ext} do
      {:zip, ext} when ext in @zip_family ->
        {:ok, @by_extension[ext]}

      {:ole, ext} when ext in @ole_family ->
        {:ok, @by_extension[ext]}

      {:zip, _} ->
        {:error, :mismatch}

      {:ole, _} ->
        {:error, :mismatch}

      {nil, ext} when ext in @text_family ->
        if text?(head), do: {:ok, @by_extension[ext]}, else: {:error, :mismatch}

      {nil, _} ->
        {:error, :unknown}

      {type, ext} ->
        if @by_extension[ext] in [type, nil], do: {:ok, type}, else: {:error, :mismatch}
    end
  end

  defp signature(<<"%PDF-", _::binary>>), do: "application/pdf"
  defp signature(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>), do: "image/png"
  defp signature(<<0xFF, 0xD8, 0xFF, _::binary>>), do: "image/jpeg"
  defp signature(<<"GIF87a", _::binary>>), do: "image/gif"
  defp signature(<<"GIF89a", _::binary>>), do: "image/gif"
  defp signature(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: "image/webp"
  defp signature(<<_::binary-size(4), "ftypM4A", _::binary>>), do: "audio/mp4"
  defp signature(<<_::binary-size(4), "ftyp", _::binary>>), do: "video/mp4"
  defp signature(<<"ID3", _::binary>>), do: "audio/mpeg"
  defp signature(<<0xFF, b, _::binary>>) when b in [0xFB, 0xF3, 0xF2], do: "audio/mpeg"
  defp signature(<<"PK", 3, 4, _::binary>>), do: :zip
  defp signature(<<0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, _::binary>>), do: :ole
  defp signature(_head), do: nil

  # Texto: UTF-8 válido (tolerando un carácter cortado al final) y sin NUL.
  defp text?(head) do
    not String.contains?(head, <<0>>) and
      (String.valid?(head) or String.valid?(binary_part(head, 0, max(byte_size(head) - 3, 0))))
  end

  defp extension(filename) do
    filename |> Path.extname() |> String.trim_leading(".") |> String.downcase()
  end
end
