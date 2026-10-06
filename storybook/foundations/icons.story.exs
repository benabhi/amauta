defmodule Storybook.Foundations.Icons do
  use PhoenixStorybook.Story, :page

  def doc, do: "Phosphor Icons (MIT): regular en la interfaz, duotone en estados vacíos."

  def render(assigns) do
    {icons, _} = Code.eval_file("assets/icons.exs")
    assigns = assign(assigns, icons: icons)

    ~H"""
    <div class="amauta bg-paper space-y-6 p-6 font-sans text-ink">
      <section :for={{weight, names} <- @icons}>
        <h2 class="mb-3 font-display text-xl font-semibold">{weight}</h2>
        <div class="grid grid-cols-3 gap-3 sm:grid-cols-6">
          <div
            :for={name <- names}
            class="flex flex-col items-center gap-2 rounded-card border border-line bg-surface p-3"
          >
            <AmautaWeb.CoreComponents.icon
              name={if weight == :regular, do: name, else: "#{name}-#{weight}"}
              class="size-8 text-anil-deep"
            />
            <span class="text-center font-mono text-xs">{name}</span>
          </div>
        </div>
      </section>
    </div>
    """
  end
end
