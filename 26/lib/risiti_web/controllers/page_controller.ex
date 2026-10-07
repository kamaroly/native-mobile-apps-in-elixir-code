defmodule RisitiWeb.PageController do
  use RisitiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
