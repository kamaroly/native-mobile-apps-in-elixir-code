defmodule RisitiApp.Screens.ReceiptFormScreenTest do
  use Mob.ScreenCase

  import RisitiApp.ScreenHelpers

  alias RisitiApp.Transactions
  alias RisitiApp.Screens.{ReceiptFormScreen, ReceiptsScreen}

  setup :checkout_repo

  # Types into the fields the way the phone does: one {:change, ...} each.
  defp fill_in(view, fields) do
    Enum.reduce(fields, view, fn {field, value}, view ->
      render_info(view, {:change, field, value})
    end)
  end

  test "a new receipt starts on today, in Other" do
    view = mount_screen(ReceiptFormScreen)

    assert assigns(view).date == Date.to_iso8601(Transactions.today())
    assert assigns(view).category == "Other"
    assert_renderable(rendered(view))
  end

  test "saving a new receipt goes back to a fresh list" do
    view =
      ReceiptFormScreen
      |> mount_screen()
      |> fill_in(vendor: "Java House", amount: "870", date: "2026-10-02")
      |> render_info({:alert, :category_1})
      |> render_info({:tap, :save})

    assert navigated_to(view) == ReceiptsScreen

    assert [%{vendor: "Java House", amount_cents: 87_000, category: "Meals & Entertainment"}] =
             Transactions.list_transactions()
  end

  test "a bad date and amount are caught before Ecto sees them" do
    view =
      ReceiptFormScreen
      |> mount_screen()
      |> fill_in(vendor: "Java House", amount: "abc", date: "2/10/2026")
      |> render_info({:tap, :save})

    assert navigated_to(view) == nil
    assert assigns(view).errors.date == "use the format 2026-09-23"
    assert assigns(view).errors.amount == "enter an amount like 1250 or 1,250.50"
    assert text(rendered(view)) =~ "use the format 2026-09-23"
  end

  test "the changeset's errors are shown in words" do
    view =
      ReceiptFormScreen
      |> mount_screen()
      |> fill_in(vendor: " ", amount: "0")
      |> render_info({:tap, :save})

    assert assigns(view).errors == %{
             vendor: "Vendor can't be blank",
             amount: "Amount must be more than zero"
           }

    assert Transactions.list_transactions() == []
  end

  test "editing starts from the saved values and updates them" do
    naivas = insert_transaction(vendor: "Naivas", amount_cents: 345_050)

    view = mount_screen(ReceiptFormScreen, %{id: naivas.id})
    assert %{vendor: "Naivas", amount: "3450.50"} = assigns(view)

    view = view |> fill_in(amount: "3,500") |> render_info({:tap, :save})

    assert navigated_to(view) == ReceiptsScreen
    assert Transactions.get_transaction!(naivas.id).amount_cents == 350_000
  end

  test "a paid transaction stays as it was paid" do
    {:ok, approved} = Transactions.decide(insert_transaction(amount_cents: 345_050), "approved")
    {:ok, paid} = Transactions.decide(approved, "paid")

    view =
      ReceiptFormScreen
      |> mount_screen(%{id: paid.id})
      |> fill_in(amount: "1")
      |> render_info({:tap, :save})

    assert navigated_to(view) == nil
    assert_received {:native, :toast, ["This one has been paid, so it can't change"]}
    assert Transactions.get_transaction!(paid.id).amount_cents == 345_050
  end

  test "confirming the delete alert removes the receipt" do
    naivas = insert_transaction(vendor: "Naivas")

    view =
      ReceiptFormScreen
      |> mount_screen(%{id: naivas.id})
      |> render_info({:alert, :confirm_delete})

    assert navigated_to(view) == ReceiptsScreen
    assert Transactions.get_transaction(naivas.id) == nil
  end
end
