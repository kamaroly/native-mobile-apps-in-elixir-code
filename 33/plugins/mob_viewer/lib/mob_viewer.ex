defmodule MobViewer do
  @moduledoc """
  Opens a file from the app's own storage in the phone's viewer for that
  kind of file: a PDF reader, the gallery.

      socket = MobViewer.view(socket, path, "application/pdf")

      def handle_info({:viewer, :error, json}, socket)

  Android won't let another app read a path inside ours, so the bridge
  copies the file into the app's cache, where the project's FileProvider
  can share it, and opens it with a `content://` address and a one-off
  permission to read it.

  Nothing arrives when the viewer opens. If it can't, an error does; decode
  it with `decode/1`: `%{"message" => reason}`, where reason is
  `"no_viewer"` (no app on the phone opens that type), `"not_found"` (no
  such file), `"not_available"` (not Android), or what Android said.
  """

  @doc "Opens `path` in the phone's viewer for `mime`. See the module docs."
  @spec view(socket, String.t(), String.t()) :: socket when socket: term()
  def view(socket, path, mime) do
    args = :json.encode(%{"path" => path, "mime" => mime})

    try do
      :mob_viewer_nif.view_file(IO.iodata_to_binary(args))
    rescue
      # No native side on this platform (iOS for now, or a host build).
      error in ErlangError ->
        if error.original == :nif_not_loaded do
          send(self(), {:viewer, :error, ~s({"message":"not_available"})})
        else
          reraise error, __STACKTRACE__
        end
    end

    socket
  end

  @doc "Decodes the JSON payload of a `{:viewer, :error, json}` message."
  @spec decode(binary()) :: map()
  def decode(json) when is_binary(json) do
    {decoded, :ok, ""} = :json.decode(json, :ok, %{null: nil})
    decoded
  end
end
