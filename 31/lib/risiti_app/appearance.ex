defmodule RisitiApp.Appearance do
  @moduledoc """
  Light / dark / follow-the-system theme choice, saved in `Mob.State` so it
  survives a restart.

  `Mob.Theme.AdaptiveWatcher` re-applies its registered "adaptive" theme
  whenever the phone's appearance flips. Registering the user's choice there
  (rather than always `RisitiApp.Theme.Adaptive`) keeps an explicit Light or
  Dark choice from being overridden when the phone switches.
  """

  alias Mob.Theme.AdaptiveWatcher

  @modes [:system, :light, :dark]
  @key :appearance

  def modes, do: @modes

  @doc "The saved choice, `:system` until the user picks one."
  def current do
    case Mob.State.get(@key, :system) do
      mode when mode in @modes -> mode
      _ -> :system
    end
  end

  @doc "Saves `mode` and applies it immediately."
  def choose(mode) when mode in @modes do
    :ok = Mob.State.put(@key, mode)
    apply_mode(mode)
  end

  @doc "Applies the saved choice. Called once at boot."
  def apply_saved, do: apply_mode(current())

  def label(:system), do: "System"
  def label(:light), do: "Light"
  def label(:dark), do: "Dark"

  defp apply_mode(mode) do
    theme = theme_module(mode)
    AdaptiveWatcher.register_adaptive(theme)
    Mob.Theme.set(theme)
  end

  defp theme_module(:system), do: RisitiApp.Theme.Adaptive
  defp theme_module(:light), do: RisitiApp.Theme.Light
  defp theme_module(:dark), do: RisitiApp.Theme.Dark
end
