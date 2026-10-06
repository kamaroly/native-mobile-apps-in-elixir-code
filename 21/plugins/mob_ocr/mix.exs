defmodule MobOcr.MixProject do
  use Mix.Project

  def project do
    [
      app: :mob_ocr,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: deps(),
      description: "On-device receipt photo processing + OCR (ML Kit) for Mob apps"
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps, do: [{:mob, "~> 0.9"}]
end
