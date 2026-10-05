defmodule RisitiApp.Screens.ReceiptsScreenTest do
  use Mob.ScreenCase

  alias RisitiApp.Screens.ReceiptsScreen

  test "shows the receipts heading" do
    view = mount_screen(ReceiptsScreen)
    assert text(view) =~ "Receipts"
    assert_renderable(view)
  end
end
