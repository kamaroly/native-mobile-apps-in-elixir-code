defmodule RisitiWeb.Plugs.RequireWebUser do
  @moduledoc "Web pages need someone signed in; anyone else goes to the sign-in page."

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  def init(opts), do: opts

  def call(%{assigns: %{current_user: %{}}} = conn, _opts), do: conn
  def call(conn, _opts), do: conn |> redirect(to: "/sign-in") |> halt()
end
