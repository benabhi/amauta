defmodule Storybook.Foundations.Colors do
  use PhoenixStorybook.Story, :page

  def doc, do: "Neutros y familias pastel con nombres de tintes andinos (ERS 6.5.2, DEC-017)."

  @neutrals ~w(paper surface surface-sunken ink ink-muted line primary)

  def render(assigns) do
    assigns =
      assign(assigns,
        neutrals: @neutrals,
        families: AmautaWeb.CoreComponents.families()
      )

    ~H"""
    <div class="amauta bg-paper space-y-8 p-6 font-sans text-ink">
      <section>
        <h2 class="mb-3 font-display text-xl font-semibold">Neutros</h2>
        <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div :for={token <- @neutrals} class="overflow-hidden rounded-card border border-line">
            <div class="h-16" style={"background: var(--#{token})"} />
            <p class="bg-surface px-3 py-2 font-mono text-xs">--color-{token}</p>
          </div>
        </div>
      </section>

      <section>
        <h2 class="mb-3 font-display text-xl font-semibold">Familias pastel</h2>
        <p class="mb-3 text-sm text-ink-muted">
          Cada familia tiene un fondo pastel y un tono profundo para el texto encima.
          Todos los pares superan 4,5:1 en claro y en oscuro (verificado en la CI).
        </p>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <div
            :for={family <- @families}
            class="rounded-card p-4"
            style={"background: var(--#{family}-soft); color: var(--#{family}-deep)"}
          >
            <p class="font-display text-lg font-semibold">{family}</p>
            <p class="font-mono text-xs">--color-{family}-soft / -deep</p>
          </div>
        </div>
      </section>
    </div>
    """
  end
end
