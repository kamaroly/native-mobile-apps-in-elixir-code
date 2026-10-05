import Config

# Register the Repo so Mix tasks (mix ecto.create, mix ecto.migrate) can
# discover it. The actual database path is configured at runtime in
# RisitiApp.Repo.init/2 via the MOB_DATA_DIR environment variable.
config :risiti_app, ecto_repos: [RisitiApp.Repo]

# Wire the Repo into Mob.ScreenState so screens using `vsn:` get automatic
# state persistence. Remove this line to disable screen state persistence.
config :mob, :repo, RisitiApp.Repo

# Our own composite tags, so the ~MOB sigil knows them at compile time.
config :mob, :extra_tags, ~w(Header TransactionItem)

# Tests run each case in a transaction that is rolled back afterwards.
if config_env() == :test do
  config :risiti_app, RisitiApp.Repo, pool: Ecto.Adapters.SQL.Sandbox
  config :logger, level: :warning
  # Screens' calls to the phone become {:native, name, args} messages.
  config :risiti_app, :native, false
end
