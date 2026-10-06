defmodule RisitiApp.Native do
  @moduledoc """
  The native calls screens make: the camera permission, the camera, the
  phone's gallery, the fingerprint check, reading receipts, the QR scanner,
  KRA lookups, the browser, the file picker, alerts, action sheets and toasts.

  They go straight to the phone's native layer, which does not exist under
  `mix test`. With `config :risiti_app, :native, false` each call instead
  sends `{:native, name, args}` to the calling process, so a screen test can
  assert what the screen asked the phone to do and then feed back the reply
  message.
  """

  alias RisitiApp.Receipts.KraReceipt

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

  @doc """
  Straightens and shrinks the camera's photo, saves it at `dest`, and reads
  its text, all on the phone (see `MobOcr`). Replies `{:ocr, :result, json}`
  or `{:ocr, :error, json}`.
  """
  def process_photo(socket, tmp, dest),
    do: call(socket, :process_photo, [tmp, dest], &MobOcr.process(&1, tmp, save_to: dest))

  @doc """
  Opens the QR scanner. Replies `{:scan, :result, %{value: text}}`,
  `{:scan, :cancelled}`, `{:scan, :permission_denied}` or
  `{:scan, :not_available}`.
  """
  def scan_qr(socket), do: call(socket, :scan_qr, [], &MobScanner.scan(&1, formats: [:qr]))

  @doc """
  Looks a receipt up on KRA's page, in a separate process so the screen
  stays responsive. Replies `{:kra, :result, details}` or
  `{:kra, :error, reason}`, with `ref` added at the end when one is given:
  `{:kra, :result, details, ref}`.
  """
  def lookup_kra(socket, url, ref \\ nil) do
    args = if ref == nil, do: [url], else: [url, ref]

    call(socket, :lookup_kra, args, fn socket ->
      screen = self()
      Task.start(fn -> send(screen, kra_reply(KraReceipt.fetch(url), ref)) end)
      socket
    end)
  end

  defp kra_reply({:ok, details}, nil), do: {:kra, :result, details}
  defp kra_reply({:error, reason}, nil), do: {:kra, :error, reason}
  defp kra_reply({:ok, details}, ref), do: {:kra, :result, details, ref}
  defp kra_reply({:error, reason}, ref), do: {:kra, :error, reason, ref}

  @doc "Opens a web page in the phone's browser."
  def open_url(socket, url),
    do:
      call(socket, :open_url, [url], fn socket ->
        Mob.Device.open_url(url)
        socket
      end)

  @doc """
  Opens the phone's file picker for images and PDFs. Replies
  `{:files, :picked, items}` or `{:files, :cancelled}` (see `Mob.Files`).
  """
  def pick_files(socket),
    do: call(socket, :pick_files, [], &Mob.Files.pick(&1, types: [:images, :pdf]))

  @doc "Opens a file from the app's storage in the phone's own viewer: a PDF reader, the gallery."
  def open_file(socket, path),
    do:
      call(socket, :open_file, [path], fn socket ->
        Mob.Device.open_url(path)
        socket
      end)

  @doc "A dialog. The tapped button replies `{:alert, action}`."
  def alert(socket, opts), do: call(socket, :alert, [opts], &Mob.Alert.alert(&1, opts))

  @doc "A list of choices from the bottom of the screen. Replies `{:alert, action}`."
  def action_sheet(socket, opts),
    do: call(socket, :action_sheet, [opts], &Mob.Alert.action_sheet(&1, opts))

  defp call(socket, name, args, native) do
    if Application.get_env(:risiti_app, :native, true) do
      native.(socket)
    else
      send(self(), {:native, name, args})
      socket
    end
  end
end
