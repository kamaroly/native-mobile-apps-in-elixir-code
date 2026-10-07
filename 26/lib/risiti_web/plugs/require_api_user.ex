defmodule RisitiWeb.Plugs.RequireApiUser do
  @moduledoc "API calls need a valid bearer token; anything else gets a 401."

  import Plug.Conn

  def init(opts), do: opts

  def call(%{assigns: %{current_user: %{}}} = conn, _opts), do: conn

  def call(conn, _opts) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, ~s({"error":"Sign in again"}))
    |> halt()
  end
end
