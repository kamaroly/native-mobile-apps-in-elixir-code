defmodule RisitiWeb.ClientAddress do
  @moduledoc """
  The client's address, for the per-address limit on SMS codes. Behind a
  reverse proxy every request comes from the proxy, so it's the last
  address the proxy added to X-Forwarded-For. Earlier entries come from
  the client, and can be made up.
  """

  @doc "From a request."
  @spec of_conn(Plug.Conn.t()) :: String.t() | nil
  def of_conn(conn),
    do: from(Plug.Conn.get_req_header(conn, "x-forwarded-for"), conn.remote_ip)

  @doc """
  From a LiveView socket, during `mount/3` (the endpoint's socket must pass
  `:peer_data` and `:x_headers` in `connect_info`).
  """
  @spec of_socket(Phoenix.LiveView.Socket.t()) :: String.t() | nil
  def of_socket(socket) do
    forwarded =
      for {"x-forwarded-for", value} <-
            Phoenix.LiveView.get_connect_info(socket, :x_headers) || [],
          do: value

    peer = Phoenix.LiveView.get_connect_info(socket, :peer_data)
    from(forwarded, peer && peer.address)
  end

  defp from([_ | _] = forwarded, _remote),
    do: forwarded |> Enum.join(",") |> String.split(",") |> List.last() |> String.trim()

  defp from([], nil), do: nil
  defp from([], remote), do: remote |> :inet.ntoa() |> to_string()
end
