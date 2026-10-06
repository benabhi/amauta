defmodule AmautaWeb.Terminology do
  @moduledoc """
  Terminología de la institución en las plantillas (ERS 4.9).

    * `term(scope, :course)` → «curso» o «materia».
    * `term(scope, :course, 3)` → «cursos» o «materias».
    * `term_title(scope, :course)` → «Curso» o «Materia».
    * `gettext_term(scope, :course, "New %{term}")` → «Nuevo curso» o
      «Nueva materia».

  `gettext_term/4` elige la traducción según el género gramatical del
  término: cada mensaje tiene dos entradas en los `.po`, con contexto
  `masculine` y `feminine`. Las variables `%{term}` (singular) y `%{terms}`
  (plural) están siempre disponibles.
  """
  alias Amauta.Terminology

  defdelegate term(tenant, key, count \\ 1), to: Terminology, as: :name
  defdelegate term_title(tenant, key, count \\ 1), to: Terminology, as: :title

  defmacro gettext_term(tenant, key, msgid, bindings \\ []) do
    quote do
      term = Amauta.Terminology.term(unquote(tenant), unquote(key))

      bindings =
        Keyword.merge([term: term.singular, terms: term.plural], unquote(bindings))

      case term.gender do
        :masculine -> pgettext("masculine", unquote(msgid), bindings)
        :feminine -> pgettext("feminine", unquote(msgid), bindings)
      end
    end
  end
end
