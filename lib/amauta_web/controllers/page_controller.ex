defmodule AmautaWeb.PageController do
  use AmautaWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
