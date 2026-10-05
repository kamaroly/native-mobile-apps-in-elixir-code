defmodule RisitiApp.Screens.SettingsScreenTest do
  use Mob.ScreenCase, async: false

  alias RisitiApp.Screens.SettingsScreen

  test "offers the three appearances" do
    view = mount_screen(SettingsScreen)

    for label <- ["System", "Light", "Dark"],
        do: assert(find(view, :box, accessibility_label: "Appearance: #{label}"))

    assert_renderable(view)
  end

  test "tapping Dark switches the theme and marks Dark as chosen" do
    view = SettingsScreen |> mount_screen() |> render_info({:tap, {:appearance, :dark}})

    assert assigns(view).appearance == :dark

    assert find(view, :box, accessibility_label: "Appearance: Dark").props.background ==
             :primary

    assert RisitiApp.Theme.dark?()
  after
    Mob.Theme.set(RisitiApp.Theme.Light)
  end
end
