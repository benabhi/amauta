// Completa en el navegador el HTML que genera el servidor
// (Amauta.RichText.to_html/1): fórmulas con KaTeX y resaltado de código.
// Se carga bajo demanda desde el hook RichContent, solo si hacen falta.
import katex from "katex"
import hljs from "highlight.js/lib/core"
import bash from "highlight.js/lib/languages/bash"
import c from "highlight.js/lib/languages/c"
import cpp from "highlight.js/lib/languages/cpp"
import css from "highlight.js/lib/languages/css"
import elixir from "highlight.js/lib/languages/elixir"
import java from "highlight.js/lib/languages/java"
import javascript from "highlight.js/lib/languages/javascript"
import json from "highlight.js/lib/languages/json"
import python from "highlight.js/lib/languages/python"
import sql from "highlight.js/lib/languages/sql"
import xml from "highlight.js/lib/languages/xml"
import {ensureKatexCss} from "./katex_css"

const languages = {bash, c, cpp, css, elixir, java, javascript, json, python, sql, xml}
for (const [name, language] of Object.entries(languages)) hljs.registerLanguage(name, language)

export const enhance = (root) => {
  const formulas = root.querySelectorAll(".rich-math:not([data-rendered])")
  if (formulas.length > 0) ensureKatexCss()

  for (const el of formulas) {
    katex.render(el.dataset.latex || "", el, {throwOnError: false, displayMode: true})
    el.dataset.rendered = ""
  }

  for (const el of root.querySelectorAll("pre code:not([data-highlighted])")) {
    hljs.highlightElement(el)
  }
}
