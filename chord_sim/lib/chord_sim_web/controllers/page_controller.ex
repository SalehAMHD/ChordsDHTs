defmodule ChordSimWeb.PageController do
  use ChordSimWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
