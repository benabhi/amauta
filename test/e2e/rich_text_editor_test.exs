defmodule AmautaWeb.E2E.RichTextEditorTest do
  @moduledoc """
  Editor de bloques en un navegador real (RF-CON-003, riesgo del MVP
  «integración del editor con LiveView»): escribir, usar el menú «/»,
  guardar y ver el contenido publicado, con la descripción de un trayecto.
  """
  use AmautaWeb.E2ECase

  alias Amauta.{Actions, Pathways}
  alias Amauta.Pathways.Actions.CreatePathway
  alias AmautaWeb.Paths

  setup do
    user = user_fixture()
    assign!(user, "institution_admin", :institution)
    admin = Amauta.Scope.for_user(institution(), user)
    {:ok, pathway} = Actions.run(CreatePathway, admin, %{"name" => "Lic. en Sistemas"})
    %{user: user, pathway: pathway}
  end

  @editor "#pathway_form [data-editor-content] .ProseMirror"

  test "escribe con el menú «/», guarda y muestra el contenido", ctx do
    %{conn: conn, user: user, pathway: pathway} = ctx

    conn
    |> log_in(user, Paths.edit_pathway(institution(), pathway))
    |> assert_has(@editor)
    |> click(@editor)
    |> type(@editor, "/tit")
    |> assert_has(".rich-slash-menu [role=option]", text: "Title")
    |> press(@editor, "Enter")
    |> type(@editor, "Presentación")
    |> press(@editor, "Enter")
    |> type(@editor, "Una carrera de ")
    |> press(@editor, "Control+b")
    |> type(@editor, "cinco años")
    |> press(@editor, "Control+b")
    |> press(@editor, "Enter")
    |> type(@editor, "/form")
    |> press(@editor, "Enter")
    |> type(".rich-math-edit textarea", "a^2 + b^2 = c^2")
    |> assert_has(".rich-math-preview .katex")
    |> click_button("Save")
    |> assert_has("#pathway-description h2", text: "Presentación")
    |> assert_has("#pathway-description strong", text: "cinco años")
    |> assert_has("#pathway-description .rich-math .katex")

    assert %{
             "content" => [
               %{"type" => "heading"},
               %{"type" => "paragraph"},
               %{"type" => "mathBlock"} | _
             ]
           } =
             Pathways.get(institution(), pathway.id).description
  end
end
