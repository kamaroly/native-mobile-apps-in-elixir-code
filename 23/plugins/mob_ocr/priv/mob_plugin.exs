# mob_ocr — receipt photo processing + on-device OCR and QR detection (ML Kit).
%{
  name: :mob_ocr,
  mob_version: "~> 0.9",
  plugin_spec_version: 1,
  nifs: [
    # Android only for now: zig NIF bridging to io.mob.ocr.MobOcrBridge.
    # iOS would use Apple Vision (VNRecognizeTextRequest); until then the
    # Elixir wrapper reports {:ocr, :error, %{"message" => "not_available"}}.
    %{module: :mob_ocr_nif, native_dir: "priv/native/jni", lang: :zig, platform: :android}
  ],
  android: %{
    bridge_kt: "priv/native/android/MobOcrBridge.kt",
    bridge_class: "io.mob.ocr.MobOcrBridge",
    gradle_deps: [
      # Bundled Latin model: works offline from first launch (no Play
      # Services model download). 16.0.1 is the release ML Kit lists with
      # 16 KB page-size support.
      "com.google.mlkit:text-recognition:16.0.1",
      # Same artifact/version mob_scanner already pulls in; used to find the
      # eTIMS QR code in the receipt photo itself.
      "com.google.mlkit:barcode-scanning:17.3.0"
    ]
  }
}
