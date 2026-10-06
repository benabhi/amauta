defmodule Storybook.Root do
  # Raíz del catálogo vivo de Amauta (ERS 6.5.7).
  use PhoenixStorybook.Index

  def folder_icon, do: {:fa, "book-open", :light, "psb:mr-1"}
  def folder_name, do: "Amauta"

  def entry("welcome") do
    [name: "Bienvenida", icon: {:fa, "hand-wave", :thin}]
  end
end
