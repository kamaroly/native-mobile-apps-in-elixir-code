defmodule RisitiApp.Screens.ReceiptsScreenTest do
  use Mob.ScreenCase

  import RisitiApp.ScreenHelpers

  alias RisitiApp.Transactions
  alias RisitiApp.Screens.{DateRangeScreen, ReceiptFormScreen, ReceiptsScreen, SettingsScreen}

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

  defp vendors(view), do: view |> assigns() |> Map.fetch!(:items) |> Enum.map(& &1.vendor)

  describe "the details sheet" do
    test "selecting a row opens its sheet; Close shuts it" do
      insert_transaction(vendor: "Java House", amount_cents: 87_000)

      view = ReceiptsScreen |> mount_screen() |> render_info({:select, :receipts, 0})

      assert assigns(view).selected.vendor == "Java House"
      assert find(rendered(view), :sheet, [])
      assert text(rendered(view)) =~ "Ksh 870.00"
      assert_renderable(rendered(view))

      view = render_info(view, {:dismiss, :close_transaction})
      refute find(rendered(view), :sheet, [])
    end

    test "Edit opens that receipt in the form" do
      java = insert_transaction(vendor: "Java House")

      view =
        ReceiptsScreen
        |> mount_screen()
        |> render_info({:select, :receipts, 0})
        |> render_info({:tap, :edit_transaction})

      assert {:push, ReceiptFormScreen, %{id: id}} = view.socket.__mob__.nav_action
      assert id == java.id
      assert assigns(view).selected == nil
    end

    test "Delete asks first, then removes it" do
      insert_transaction(vendor: "Java House")

      view =
        ReceiptsScreen
        |> mount_screen()
        |> render_info({:select, :receipts, 0})
        |> render_info({:tap, :delete_transaction})

      assert_received {:native, :alert, [opts]}
      assert opts[:title] == "Delete this transaction?"
      assert vendors(view) == ["Java House"]

      view = render_info(view, {:alert, :confirm_delete})

      assert vendors(view) == []
      assert Transactions.list_transactions() == []
      assert_received {:native, :toast, ["Deleted"]}
    end
  end

  describe "search" do
    test "narrows the list as you type, and hides the spend card" do
      insert_transaction(vendor: "Naivas Supermarket")
      insert_transaction(vendor: "Java House")

      view = ReceiptsScreen |> mount_screen() |> render_info({:tap, :toggle_search})
      refute text(rendered(view)) =~ "Spent this month"

      view = render_info(view, {:change, :search, "java"})
      assert vendors(view) == ["Java House"]

      view = render_info(view, {:change, :search, "zzz"})
      assert text(rendered(view)) =~ "Nothing matches your search."
    end

    test "closing it clears the search" do
      insert_transaction(vendor: "Naivas Supermarket")
      insert_transaction(vendor: "Java House")

      view =
        ReceiptsScreen
        |> mount_screen()
        |> render_info({:tap, :toggle_search})
        |> render_info({:change, :search, "java"})
        |> render_info({:tap, :toggle_search})

      assert assigns(view).query == ""
      assert length(vendors(view)) == 2
      assert text(rendered(view)) =~ "Spent this month"
    end
  end

  describe "the month picker" do
    test "offers the last twelve months and shows the one picked" do
      last_month = Transactions.today() |> Date.beginning_of_month() |> Date.add(-1)
      insert_transaction(amount_cents: 100_000)
      insert_transaction(amount_cents: 250_000, date: last_month)

      view = ReceiptsScreen |> mount_screen() |> render_info({:tap, :pick_month})

      assert_received {:native, :action_sheet, [opts]}
      assert length(opts[:buttons]) == 13
      assert hd(opts[:buttons])[:label] == Calendar.strftime(Transactions.today(), "%B %Y")

      view = render_info(view, {:alert, :month_1})

      assert text(rendered(view)) =~ "Spent in #{Calendar.strftime(last_month, "%B %Y")}"
      assert text(rendered(view)) =~ "Ksh 2,500"
    end
  end

  describe "dates" do
    setup do
      today = Transactions.today()
      insert_transaction(vendor: "Today", date: today)
      insert_transaction(vendor: "Last year", date: Date.add(today, -400))
      [today: today]
    end

    test "a preset narrows the list, and the pill says which" do
      view = ReceiptsScreen |> mount_screen() |> render_info({:tap, :pick_period})

      assert_received {:native, :action_sheet, [opts]}
      assert Enum.any?(opts[:buttons], &(&1[:action] == :choose_dates))

      view = render_info(view, {:alert, :period_last_7_days})

      assert vendors(view) == ["Today"]
      assert find(rendered(view), :row, accessibility_label: "Dates: Last 7 days. Change dates")
    end

    test "Choose dates opens the date screen, which answers with the dates", %{today: today} do
      view = ReceiptsScreen |> mount_screen() |> render_info({:alert, :choose_dates})

      assert {:push, DateRangeScreen, %{from: nil, to: nil, notify: pid}} =
               view.socket.__mob__.nav_action

      assert pid == self()

      view = render_info(view, {:dates_chosen, nil, Date.add(today, -1)})
      assert vendors(view) == ["Last year"]
      assert text(rendered(view)) =~ "Up to "
    end
  end

  test "Add and Settings open their screens" do
    view = ReceiptsScreen |> mount_screen() |> render_info({:tap, :add_manual})
    assert navigated_to(view) == ReceiptFormScreen

    view = ReceiptsScreen |> mount_screen() |> render_info({:tap, :open_settings})
    assert navigated_to(view) == SettingsScreen
  end
end
