import Config

# Register the Repo so Mix tasks (mix ecto.create, mix ecto.migrate) can
# discover it. The actual database path is configured at runtime in
# RisitiApp.Repo.init/2 via the MOB_DATA_DIR environment variable.
config :risiti_app, ecto_repos: [RisitiApp.Repo]

# Wire the Repo into Mob.ScreenState so screens using `vsn:` get automatic
# state persistence. Remove this line to disable screen state persistence.
config :mob, :repo, RisitiApp.Repo

# Our own composite tags, so the ~MOB sigil knows them at compile time.
config :mob, :extra_tags, ~w(Header TransactionItem SearchField TransactionSheet)

# Sign in with Google (see MobGoogle): the *Web* OAuth client id from the
# server's Google Cloud project. Part IV sets it, with the server.
config :risiti_app, :google_client_id, nil

# The Risiti server. mob_dev evaluates this file when it builds the app and
# ships the result to the phone, so this is what the phone uses. In
# development it's the server on your computer, which the phone reaches
# through `adb reverse tcp:4000 tcp:4000`; a release talks to your own
# server (Chapter 33).
config :risiti_app,
       :api_url,
       if(config_env() == :prod, do: "https://risiti.example.com", else: "http://127.0.0.1:4000")

# Push notifications (Chapter 32). Off until Firebase is set up for the
# app: a google-services.json in android/app, and the server's key.
config :risiti_app, :push, false

# Tests run each case in a transaction that is rolled back afterwards.
if config_env() == :test do
  config :risiti_app, RisitiApp.Repo, pool: Ecto.Adapters.SQL.Sandbox
  config :logger, level: :warning
  # Screens' calls to the phone become {:native, name, args} messages.
  config :risiti_app, :native, false
  # Server calls go to a scripted stand-in (test/support/fake_server.ex).
  config :risiti_app, :http, RisitiApp.FakeServer
  config :risiti_app, :api_url, "http://risiti.test"
  # Pushes are on; the native calls are faked, as above.
  config :risiti_app, :push, true
  # Sign in with Google is offered; the native call is faked, as above.
  config :risiti_app, :google_client_id, "risiti-web.apps.googleusercontent.com"
end
