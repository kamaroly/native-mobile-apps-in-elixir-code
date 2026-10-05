defmodule RisitiApp.Screens.ReceiptsScreenTest do
  use Mob.ScreenCase

  import RisitiApp.ScreenHelpers

  alias RisitiApp.Screens.{ReceiptFormScreen, ReceiptsScreen, SettingsScreen}

  setup :checkout_repo

  test "an empty book says how to start" do
    view = mount_screen(ReceiptsScreen)

    assert text(rendered(view)) =~ "No receipts yet"
    assert_renderable(rendered(view))
  end

  test "shows this month's spend and every receipt" do
    insert_transaction(vendor: "Naivas Supermarket", amount_cents: 345_050)
    insert_transaction(vendor: "TotalEnergies Westlands", category: "Fuel", amount_cents: 450_000)

    view = mount_screen(ReceiptsScreen)
    text = text(rendered(view))

    assert text =~ "Spent this month"
    assert text =~ "Ksh 7,950.50"
    assert text =~ "Naivas Supermarket"
    assert text =~ "Ksh 3,450.50"
    assert_renderable(rendered(view))
  end

  test "the Fuel pill keeps only fuel and transport" do
    insert_transaction(vendor: "Naivas Supermarket")
    insert_transaction(vendor: "TotalEnergies Westlands", category: "Fuel")
    insert_transaction(vendor: "Little Cab", category: "Transport")

    view = ReceiptsScreen |> mount_screen() |> render_info({:tap, {:group, :fuel}})

    assert view |> assigns() |> Map.fetch!(:items) |> Enum.map(& &1.vendor) |> Enum.sort() ==
             ["Little Cab", "TotalEnergies Westlands"]
  end

  test "selecting a row opens that receipt" do
    java = insert_transaction(vendor: "Java House")

    view = ReceiptsScreen |> mount_screen() |> render_info({:select, :receipts, 0})

    assert navigated_to(view) == ReceiptFormScreen
    assert {:push, ReceiptFormScreen, %{id: id}} = view.socket.__mob__.nav_action
    assert id == java.id
  end

  test "Add and Settings open their screens" do
    view = ReceiptsScreen |> mount_screen() |> render_info({:tap, :add_manual})
    assert navigated_to(view) == ReceiptFormScreen

    view = ReceiptsScreen |> mount_screen() |> render_info({:tap, :open_settings})
    assert navigated_to(view) == SettingsScreen
  end
end
