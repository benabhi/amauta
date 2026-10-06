defmodule AmautaWeb.HomeLive do
  @moduledoc """
  Inicio de la institución. Por ahora, un saludo; el inicio adaptado al rol
  (RF-INS-002) llega en H1.
  """
  use AmautaWeb, :live_view

  alias Amauta.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {gettext("Hello, %{name}", name: @current_scope.user.first_name)}
        <:subtitle>{@current_scope.institution.name}</:subtitle>
      </.header>
      <p id="current-user">{User.display_name(@current_scope.user)}</p>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}
end
