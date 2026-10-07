// Hooks del contenido enriquecido (RF-CON-003). El editor y el visor se
// cargan bajo demanda: son las piezas pesadas (Tiptap, KaTeX, highlight.js).
export const RichTextEditor = {
  mounted() {
    import("./editor.js").then(({mountEditor}) => {
      this.editor = mountEditor(this.el)
    })
  },
  destroyed() {
    this.editor?.destroy()
  },
}

export const RichContent = {
  mounted() {
    this.enhance()
  },
  updated() {
    this.enhance()
  },
  enhance() {
    if (this.el.querySelector(".rich-math, pre code")) {
      import("./render.js").then(({enhance}) => enhance(this.el))
    }
  },
}
