defmodule RisitiWeb.ClientAddress do
  @moduledoc """
  The client's address, for the per-address limit on SMS codes. Behind a
  reverse proxy every request comes from the proxy, so it's the last
  address the proxy added to X-Forwarded-For. Earlier entries come from
  the client, and can be made up.
  """

  @spec of_conn(Plug.Conn.t()) :: String.t() | nil
  def of_conn(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [] ->
        conn.remote_ip |> :inet.ntoa() |> to_string()

      forwarded ->
        forwarded |> Enum.join(",") |> String.split(",") |> List.last() |> String.trim()
    end
  end
end
