defmodule MobGoogle.MixProject do
  use Mix.Project

  def project do
    [
      app: :mob_google,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: deps(),
      description: "Sign in with Google (Android Credential Manager) for Mob apps"
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps, do: [{:mob, "~> 0.9"}]
end
