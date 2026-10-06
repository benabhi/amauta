defmodule Storybook.Welcome do
  use PhoenixStorybook.Story, :page

  def doc, do: "Catálogo vivo del sistema de diseño de Amauta."

  def render(assigns) do
    ~H"""
    <div class="amauta bg-paper max-w-prose space-y-4 p-6 font-sans text-ink">
      <h1 class="font-display text-3xl font-semibold">Sistema de diseño de Amauta</h1>
      <p>
        Minimalismo cálido: papel y tinta, mucho aire y el pastel como protagonista
        (ERS 6.5). Cada componente de la interfaz está acá, con sus variantes y estados.
      </p>
      <p>
        Regla de oro (RNF-MAN-007): si falta un componente, se agrega a la biblioteca
        (<code class="font-mono">AmautaWeb.CoreComponents</code>) con su historia, nunca en
        la pantalla.
      </p>
      <p class="text-ink-muted">
        Usá el selector de modo del catálogo para ver cada componente en claro y oscuro.
      </p>
    </div>
    """
  end
end
