defmodule RisitiApp.Native do
  @moduledoc """
  The native calls screens make: the camera permission, the camera, toasts.

  They go straight to the phone's native layer, which does not exist under
  `mix test`. With `config :risiti_app, :native, false` each call instead
  sends `{:native, name, args}` to the calling process, so a screen test can
  assert what the screen asked the phone to do and then feed back the reply
  message.
  """

  @doc "Replies `{:permission, :camera, :granted | :denied}`."
  def request_camera(socket),
    do: call(socket, :request_camera, [], &Mob.Permissions.request(&1, :camera))

  @doc "Replies `{:camera, :photo, %{path: tmp_path}}` or `{:camera, :cancelled}`."
  def take_photo(socket),
    do: call(socket, :take_photo, [], &MobCamera.capture_photo(&1, quality: :high))

  def toast(socket, message), do: call(socket, :toast, [message], &Mob.Alert.toast(&1, message))

  defp call(socket, name, args, native) do
    if Application.get_env(:risiti_app, :native, true) do
      native.(socket)
    else
      send(self(), {:native, name, args})
      socket
    end
  end
end
