defmodule RisitiWeb.PageController do
  use RisitiWeb, :controller

  # Signed in: straight to the transactions. Otherwise, the two ways in.
  def home(%{assigns: %{current_user: %{}}} = conn, _params),
    do: redirect(conn, to: ~p"/transactions")

  def home(conn, _params), do: render(conn, :home)
end
