defmodule RisitiApp.Screens.ReceiptsScreenTest do
  use Mob.ScreenCase

  alias RisitiApp.Screens.{ReceiptFormScreen, ReceiptsScreen, SettingsScreen}

  # A <List> renders its rows lazily, so expand it the way Mob does on the
  # device before asking what text is on screen.
  defp rows(view) do
    view |> tree() |> Mob.List.expand(view.socket.__mob__.list_renderers, self())
  end

  test "shows the month's spend and every receipt" do
    view = mount_screen(ReceiptsScreen)

    assert text(rows(view)) =~ "Spent this month"
    assert text(rows(view)) =~ RisitiApp.Transactions.format_short(assigns(view).summary.total)
    assert text(rows(view)) =~ "Naivas Supermarket"
    assert text(rows(view)) =~ "Ksh 3,450.50"
    assert_renderable(rows(view))
  end

  test "the Fuel pill keeps only fuel and transport" do
    view = ReceiptsScreen |> mount_screen() |> render_info({:tap, {:group, :fuel}})

    assert Enum.map(assigns(view).items, & &1.vendor) == ["TotalEnergies Westlands", "Little Cab"]
  end

  test "selecting a row opens that receipt" do
    view = ReceiptsScreen |> mount_screen() |> render_info({:select, :receipts, 1})

    assert navigated_to(view) == ReceiptFormScreen
    assert {:push, ReceiptFormScreen, %{id: 2}} = view.socket.__mob__.nav_action
  end

  test "the form shows the receipt it was given" do
    assert text(mount_screen(ReceiptFormScreen, %{id: 2})) =~ "TotalEnergies Westlands"
    assert text(mount_screen(ReceiptFormScreen)) =~ "New receipt"
  end

  test "Add and Settings open their screens" do
    view = ReceiptsScreen |> mount_screen() |> render_info({:tap, :add_manual})
    assert navigated_to(view) == ReceiptFormScreen

    view = ReceiptsScreen |> mount_screen() |> render_info({:tap, :open_settings})
    assert navigated_to(view) == SettingsScreen
  end
end
