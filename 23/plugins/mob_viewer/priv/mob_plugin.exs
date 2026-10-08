# mob_viewer — hands a file from the app's own storage to whatever app on
# the phone opens that kind of file (a PDF reader, the gallery).
%{
  name: :mob_viewer,
  mob_version: "~> 0.9",
  plugin_spec_version: 1,
  nifs: [
    # Android only: zig NIF bridging to io.mob.viewer.MobViewerBridge. On
    # iOS (not built yet) and host builds the Elixir wrapper answers
    # {:viewer, :error, %{"message" => "not_available"}}.
    %{module: :mob_viewer_nif, native_dir: "priv/native/jni", lang: :zig, platform: :android}
  ],
  android: %{
    bridge_kt: "priv/native/android/MobViewerBridge.kt",
    bridge_class: "io.mob.viewer.MobViewerBridge"
  }
}
