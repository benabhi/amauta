defmodule Storybook.Foundations.Typography do
  use PhoenixStorybook.Story, :page

  def doc,
    do: "Atkinson Hyperlegible para la interfaz; la display se elige en la exploración visual."

  def render(assigns) do
    ~H"""
    <div class="amauta bg-paper space-y-8 p-6 font-sans text-ink">
      <section class="space-y-2">
        <h2 class="font-display text-xl font-semibold">Escala (1,25 sobre 16 px)</h2>
        <p class="text-3xl">Texto 3xl · 39 px</p>
        <p class="text-2xl">Texto 2xl · 31 px</p>
        <p class="text-xl">Texto xl · 25 px</p>
        <p class="text-lg">Texto lg · 20 px</p>
        <p class="text-base">Texto base · 16 px: Entregá tu TP antes del viernes.</p>
        <p class="text-sm">Texto sm · 14 px</p>
        <p class="font-mono text-sm tabular">Mono: 0123456789 · Il1 O0 · nota 8,75</p>
      </section>

      <section class="space-y-4">
        <h2 class="font-display text-xl font-semibold">Candidatas a display (ERS 6.5.3)</h2>
        <div class="grid gap-4 sm:grid-cols-2">
          <div class="rounded-card border border-line bg-surface p-5">
            <p class="text-sm text-ink-muted">Fraunces (provisoria)</p>
            <p class="text-3xl font-semibold" style="font-family: Fraunces">Programación I</p>
            <p class="text-xl" style="font-family: Fraunces">Escribí algo para tu clase</p>
          </div>
          <div class="rounded-card border border-line bg-surface p-5">
            <p class="text-sm text-ink-muted">Bricolage Grotesque</p>
            <p class="text-3xl font-semibold" style="font-family: 'Bricolage Grotesque'">
              Programación I
            </p>
            <p class="text-xl" style="font-family: 'Bricolage Grotesque'">
              Escribí algo para tu clase
            </p>
          </div>
        </div>
      </section>
    </div>
    """
  end
end
