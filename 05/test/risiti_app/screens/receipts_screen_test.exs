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

  test "tapping a receipt opens the form with that receipt's id" do
    view = ReceiptsScreen |> mount_screen() |> render_info({:tap, {:open_receipt, 2}})

    assert navigated_to(view) == ReceiptFormScreen
    assert {:push, ReceiptFormScreen, %{id: 2}} = view.socket.__mob__.nav_action
  end

  test "the form says which receipt it is editing" do
    assert text(mount_screen(ReceiptFormScreen, %{id: 2})) =~ "Editing receipt 2"
    assert text(mount_screen(ReceiptFormScreen)) =~ "New receipt"
  end
end
