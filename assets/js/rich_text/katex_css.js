// La hoja de estilos de KaTeX se sirve localmente (sin CDN) y se agrega a la
// página solo cuando hay fórmulas que mostrar.
export const ensureKatexCss = () => {
  if (document.getElementById("katex-css")) return
  const link = document.createElement("link")
  link.id = "katex-css"
  link.rel = "stylesheet"
  link.href = "/vendor/katex/katex.min.css"
  document.head.append(link)
}
