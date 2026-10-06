defmodule AmautaWeb.JoinLive do
  @moduledoc """
  Sumarse a un curso con su código de inscripción (RF-MAT-001). Cualquier
  persona de la institución puede usarlo; el curso tiene que estar
  publicado y tener la inscripción por código habilitada.
  """
  use AmautaWeb, :live_view

  alias Amauta.Actions
  alias Amauta.Enrollments.Actions.JoinWithCode
  alias AmautaWeb.Paths

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Join with a code"),
       form: to_form(%{"code" => params["code"] || ""}, as: "join"),
       error: nil
     )}
  end

  @impl true
  def handle_event("join", %{"join" => %{"code" => code}}, socket) do
    scope = socket.assigns.current_scope

    case Actions.run(JoinWithCode, scope, %{"code" => code}) do
      {:ok, course} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Welcome to %{name}!", name: course.name))
         |> push_navigate(to: Paths.course(scope, course))}

      {:error, :suspended} ->
        {:noreply,
         assign(socket,
           error: gettext("Your enrollment is suspended. Ask the teaching team.")
         )}

      {:error, _} ->
        {:noreply,
         assign(socket,
           form: to_form(%{"code" => code}, as: "join"),
           error: gettext("That code doesn't work. Check it with your teacher.")
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width="sm">
      <.header>
        {gettext("Join with a code")}
        <:subtitle>
          {gettext_term(
            @current_scope,
            :course,
            "The teaching team gives it to you for each %{term}."
          )}
        </:subtitle>
      </.header>

      <.form for={@form} id="join_form" phx-submit="join">
        <.input
          field={@form[:code]}
          label={gettext("Enrollment code")}
          placeholder="ABC2345"
          autocomplete="off"
          autocapitalize="characters"
          required
        />
        <.error :if={@error}>{@error}</.error>
        <.button icon="arrow-right" class="mt-2 w-full" phx-disable-with={gettext("Joining...")}>
          {gettext("Join")}
        </.button>
      </.form>
    </Layouts.app>
    """
  end
end
