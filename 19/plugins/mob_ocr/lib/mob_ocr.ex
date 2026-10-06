defmodule MobOcr do
  @moduledoc """
  On-device receipt photo processing: straighten, shrink and save the photo,
  read its text, and look for a QR code in it — in one native pass, offline.

  Android uses ML Kit (bundled Latin text recognition + barcode scanning). iOS
  is not implemented yet; there the call answers with an error message so the
  app can fall back to manual entry.

      socket = MobOcr.process(socket, tmp_photo_path, save_to: "/…/receipt-1.jpg")

      def handle_info({:ocr, :result, json}, socket)
      def handle_info({:ocr, :error, json}, socket)

  Decode the payload with `decode/1`:

    * result — `%{"text" => rows, "qr" => value | nil, "path" => saved_jpeg}`.
      `text` is rebuilt row by row from the words' positions, so a receipt
      line like `TOTAL ........ 2,450.00` stays on one line even though ML Kit
      sees the label and the amount as separate blocks.
    * error  — `%{"message" => reason, "path" => saved_jpeg | nil}`. The photo
      may still have been saved (e.g. text recognition failed after saving).

  The work runs on a background thread; the message arrives at the process
  that called `process/3` (the screen).
  """

  @default_max_dimension 2048
  @default_quality 85

  @doc """
  Process the photo at `source`.

  Options:
    * `:save_to` (required) — where to write the processed JPEG.
    * `:max_dimension` — longest side in pixels (default #{@default_max_dimension}).
    * `:quality` — JPEG quality 1..100 (default #{@default_quality}).
  """
  @spec process(socket, String.t(), keyword()) :: socket when socket: term()
  def process(socket, source, opts) do
    args =
      :json.encode(%{
        "src" => source,
        "dest" => Keyword.fetch!(opts, :save_to),
        "max_dim" => Keyword.get(opts, :max_dimension, @default_max_dimension),
        "quality" => Keyword.get(opts, :quality, @default_quality)
      })

    try do
      :mob_ocr_nif.ocr_process(IO.iodata_to_binary(args))
    rescue
      # No native implementation on this platform (iOS for now, or a host
      # dev build). Answer the same way a native failure would.
      error in ErlangError ->
        if error.original == :nif_not_loaded do
          send(self(), {:ocr, :error, ~s({"message":"not_available","path":null})})
        else
          reraise error, __STACKTRACE__
        end
    end

    socket
  end

  @doc "Decodes the JSON payload of an `{:ocr, _, json}` message (JSON null becomes nil)."
  @spec decode(binary()) :: map()
  def decode(json) when is_binary(json) do
    {decoded, :ok, ""} = :json.decode(json, :ok, %{null: nil})
    decoded
  end
end
