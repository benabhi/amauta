defmodule AmautaWeb.DesignTokensTest do
  @moduledoc """
  Contraste de los tokens de color (ERS 6.5.2, WCAG 2.2 AA): cada par de
  texto y fondo supera 4,5:1, en modo claro y en modo oscuro. Lee los
  valores directamente de `assets/css/app.css`.
  """
  use ExUnit.Case, async: true

  @css File.read!("assets/css/app.css")
  @minimum 4.5

  @pairs [
    {"ink", "paper"},
    {"ink", "surface"},
    {"ink", "surface-sunken"},
    {"ink-muted", "paper"},
    {"ink-muted", "surface"},
    {"ink-muted", "surface-sunken"},
    {"on-primary", "primary"}
  ]

  @families ~w(anil airampo chilca qolle cochinilla nogal)

  for {mode, selector} <- [light: ":root {", dark: ~s([data-theme="dark"],)] do
    describe "modo #{mode}" do
      setup do
        %{tokens: tokens(unquote(selector))}
      end

      test "texto sobre fondos neutros", %{tokens: tokens} do
        for {fg, bg} <- @pairs do
          assert_contrast(tokens, fg, bg)
        end
      end

      test "tono profundo sobre su pastel, en cada familia", %{tokens: tokens} do
        for family <- @families do
          assert_contrast(tokens, "#{family}-deep", "#{family}-soft")
        end
      end
    end
  end

  test "los dos modos definen los mismos tokens" do
    assert Map.keys(tokens(":root {")) == Map.keys(tokens(~s([data-theme="dark"],)))
  end

  defp assert_contrast(tokens, fg, bg) do
    ratio = contrast(Map.fetch!(tokens, fg), Map.fetch!(tokens, bg))

    assert ratio >= @minimum,
           "#{fg} sobre #{bg}: #{Float.round(ratio, 2)}:1 (mínimo #{@minimum}:1)"
  end

  # Variables hexadecimales del primer bloque que empieza con `selector`.
  defp tokens(selector) do
    [_, rest] = String.split(@css, selector, parts: 2)
    [block | _] = String.split(rest, "}", parts: 2)

    ~r/--([a-z-]+):\s*(#[0-9A-Fa-f]{6});/
    |> Regex.scan(block)
    |> Map.new(fn [_, name, hex] -> {name, hex} end)
  end

  defp contrast(a, b) do
    [high, low] = Enum.sort([luminance(a), luminance(b)], :desc)
    (high + 0.05) / (low + 0.05)
  end

  defp luminance("#" <> hex) do
    [r, g, b] =
      for <<channel::binary-size(2) <- hex>> do
        c = String.to_integer(channel, 16) / 255
        if c <= 0.04045, do: c / 12.92, else: :math.pow((c + 0.055) / 1.055, 2.4)
      end

    0.2126 * r + 0.7152 * g + 0.0722 * b
  end
end
