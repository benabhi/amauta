defmodule Storybook.Foundations do
  use PhoenixStorybook.Index

  def folder_name, do: "Fundamentos"
  def folder_icon, do: {:fa, "palette", :light, "psb:mr-1"}
  def entry("colors"), do: [name: "Color"]
  def entry("typography"), do: [name: "Tipografía"]
  def entry("icons"), do: [name: "Íconos"]
end
