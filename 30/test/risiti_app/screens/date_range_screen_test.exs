defmodule RisitiApp.Screens.DateRangeScreenTest do
  use Mob.ScreenCase

  alias RisitiApp.Screens.DateRangeScreen

  doctest DateRangeScreen

  test "starts from the dates it's given" do
    view = mount_screen(DateRangeScreen, %{from: ~D[2026-09-01], to: nil})
    assert %{from: "2026-09-01", to: ""} = assigns(view)
  end

  test "sends the dates back to the screen that asked, then goes back" do
    view =
      DateRangeScreen
      |> mount_screen(%{notify: self()})
      |> render_info({:change, :from, "2026-09-01"})
      |> render_info({:change, :to, "2026-09-15"})
      |> render_info({:tap, :apply})

    assert_received {:dates_chosen, ~D[2026-09-01], ~D[2026-09-15]}
    assert view.socket.__mob__.nav_action == {:pop}
  end

  test "a date it can't read stays on the screen, with the error under it" do
    view =
      DateRangeScreen
      |> mount_screen(%{notify: self()})
      |> render_info({:change, :from, "1/9/2026"})
      |> render_info({:tap, :apply})

    refute_received {:dates_chosen, _, _}
    assert text(tree(view)) =~ "use the format 2026-09-23"
  end
end
