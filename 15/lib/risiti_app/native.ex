defmodule RisitiApp.Native do
  @moduledoc """
  The native calls screens make: the camera permission, the camera, the
  phone's gallery, the fingerprint check, toasts.

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

  @doc """
  Copies a photo into the phone's gallery. Replies
  `{:storage, :saved_to_library, path}` or `{:storage, :error, :save_to_library, reason}`.
  """
  def save_to_gallery(socket, path) do
    call(
      socket,
      :save_to_gallery,
      [path],
      &Mob.Storage.Android.save_to_media_store(&1, path, :image)
    )
  end

  @doc "Replies `{:biometric, :success | :failure | :not_available}`."
  def authenticate(socket, reason),
    do: call(socket, :authenticate, [reason], &MobBiometric.authenticate(&1, reason: reason))

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
