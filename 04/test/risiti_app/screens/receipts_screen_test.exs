defmodule RisitiApp.Screens.ReceiptsScreenTest do
  use Mob.ScreenCase

  alias RisitiApp.Screens.{ReceiptFormScreen, ReceiptsScreen, SettingsScreen}

  test "shows the receipts heading" do
    view = mount_screen(ReceiptsScreen)
    assert text(view) =~ "Receipts"
    assert_renderable(view)
  end

  test "tapping Add a receipt pushes the receipt form" do
    view = ReceiptsScreen |> mount_screen() |> render_info({:tap, :add_manual})
    assert navigated_to(view) == ReceiptFormScreen
  end

  test "tapping Settings pushes the settings screen" do
    view = ReceiptsScreen |> mount_screen() |> render_info({:tap, :open_settings})
    assert navigated_to(view) == SettingsScreen
  end

  test "Go Back pops the settings screen" do
    view = SettingsScreen |> mount_screen() |> render_info({:tap, :back})
    assert navigated_to(view) == {:pop}
  end
end
