defmodule RisitiApp.AppearanceTest do
  # Mob.ScreenCase opens a throwaway Mob.State for each test.
  use Mob.ScreenCase, async: false

  alias RisitiApp.Appearance

  test "follows the system until the user chooses" do
    assert Appearance.current() == :system
  end

  test "remembers the choice and applies it" do
    Appearance.choose(:dark)

    assert Appearance.current() == :dark
    assert RisitiApp.Theme.dark?()
  after
    Mob.Theme.set(RisitiApp.Theme.Light)
  end
end
