# mob_google — Sign in with Google: an ID token from Android's Credential
# Manager, for the app's server to verify.
%{
  name: :mob_google,
  mob_version: "~> 0.9",
  plugin_spec_version: 1,
  nifs: [
    # Android only: zig NIF bridging to io.mob.google.MobGoogleBridge. On
    # iOS (not built yet) and host builds the Elixir wrapper answers
    # {:google, :error, %{"message" => "not_available"}}.
    %{module: :mob_google_nif, native_dir: "priv/native/jni", lang: :zig, platform: :android}
  ],
  android: %{
    bridge_kt: "priv/native/android/MobGoogleBridge.kt",
    bridge_class: "io.mob.google.MobGoogleBridge",
    gradle_deps: [
      "androidx.credentials:credentials:1.3.0",
      # Lets Credential Manager use Google Play services on Android 13 and
      # older.
      "androidx.credentials:credentials-play-services-auth:1.3.0",
      "com.google.android.libraries.identity.googleid:googleid:1.1.1"
    ]
  }
}
