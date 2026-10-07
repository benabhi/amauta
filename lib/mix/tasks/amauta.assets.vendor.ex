defmodule Mix.Tasks.Amauta.Assets.Vendor do
  @shortdoc "Copia las fuentes y arma el sprite de íconos del sistema de diseño"
  @moduledoc """
  Toma las fuentes (Fontsource), los íconos (Phosphor) y KaTeX de
  `assets/node_modules` y deja en `priv/static` solo lo necesario: las
  fuentes recortadas a latín y latín extendido, con su licencia, y un sprite
  SVG con los íconos de `assets/icons.exs`.

  El resultado se versiona: en producción no hace falta Node.

      cd assets && npm install
      mix amauta.assets.vendor
  """
  use Mix.Task

  @node_modules "assets/node_modules"
  @fonts_dir "priv/static/fonts"
  @sprite "priv/static/images/icons.svg"

  @fonts [
    {"@fontsource-variable/atkinson-hyperlegible-next", "atkinson-hyperlegible-next"},
    {"@fontsource-variable/atkinson-hyperlegible-mono", "atkinson-hyperlegible-mono"},
    {"@fontsource-variable/fraunces", "fraunces"},
    {"@fontsource-variable/bricolage-grotesque", "bricolage-grotesque"}
  ]

  @impl true
  def run(_args) do
    for {package, family} <- @fonts, do: copy_font(package, family)
    build_sprite()
    copy_katex()
  end

  # KaTeX (fórmulas del contenido enriquecido): su hoja de estilos y sus
  # fuentes en woff2. La hoja la carga el navegador solo si hay fórmulas.
  defp copy_katex do
    source = Path.join([@node_modules, "katex", "dist"])
    target = "priv/static/vendor/katex"
    File.rm_rf!(target)
    File.mkdir_p!(Path.join(target, "fonts"))
    File.cp!(Path.join(source, "katex.min.css"), Path.join(target, "katex.min.css"))

    fonts = Path.wildcard(Path.join([source, "fonts", "*.woff2"]))
    for font <- fonts, do: File.cp!(font, Path.join([target, "fonts", Path.basename(font)]))

    Mix.shell().info("katex: hoja de estilos y #{length(fonts)} fuentes")
  end

  defp copy_font(package, family) do
    source = Path.join([@node_modules, package])
    target = Path.join(@fonts_dir, family)
    File.rm_rf!(target)
    File.mkdir_p!(target)

    files =
      Path.join([source, "files", "*.woff2"])
      |> Path.wildcard()
      |> Enum.filter(&(Path.basename(&1) =~ ~r/-latin(-ext)?-wght-/))

    if files == [], do: Mix.raise("no font files in #{source}: run npm install in assets/")

    for file <- files, do: File.cp!(file, Path.join(target, Path.basename(file)))
    File.cp!(Path.join(source, "LICENSE"), Path.join(target, "LICENSE"))
    Mix.shell().info("#{family}: #{length(files)} archivos")
  end

  defp build_sprite do
    {icons, _} = Code.eval_file("assets/icons.exs")

    symbols =
      for {weight, names} <- icons, name <- names do
        path =
          Path.join([
            @node_modules,
            "@phosphor-icons/core/assets",
            "#{weight}",
            file(name, weight)
          ])

        svg = File.read!(path)
        [_, view_box] = Regex.run(~r/viewBox="([^"]+)"/, svg)
        [_, inner] = Regex.run(~r/<svg[^>]*>(.*)<\/svg>/s, svg)
        id = if weight == :regular, do: name, else: "#{name}-#{weight}"
        ~s(<symbol id="#{id}" viewBox="#{view_box}">#{String.trim(inner)}</symbol>)
      end

    File.mkdir_p!(Path.dirname(@sprite))

    File.write!(@sprite, [
      ~s(<svg xmlns="http://www.w3.org/2000/svg" style="display:none">\n),
      "<!-- Phosphor Icons (MIT). Generado por mix amauta.assets.vendor. -->\n",
      Enum.intersperse(symbols, "\n"),
      "\n</svg>\n"
    ])

    Mix.shell().info("íconos: #{length(symbols)} en #{@sprite}")
  end

  defp file(name, :regular), do: "#{name}.svg"
  defp file(name, weight), do: "#{name}-#{weight}.svg"
end
