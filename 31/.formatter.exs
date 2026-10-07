[
  import_deps: [:ecto, :ecto_sql],
  plugins: [Mob.Formatter],
  subdirectories: ["priv/*/migrations"],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
