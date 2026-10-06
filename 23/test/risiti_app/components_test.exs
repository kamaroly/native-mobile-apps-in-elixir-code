defmodule RisitiApp.ComponentsTest do
  use ExUnit.Case, async: true

  import Mob.ScreenCase, only: [text: 1, find: 3, assert_renderable: 1]

  alias RisitiApp.Components.{ActionButton, Header, TransactionItem, TransactionSheet}
  alias RisitiApp.Transactions.Transaction

  doctest TransactionItem

  @java %Transaction{
    id: 1,
    vendor: "Java House",
    category: "Meals & Entertainment",
    amount_cents: 87_000,
    date: ~D[2026-10-02]
  }

  test "Header shows the kicker and title, and a back button only when asked" do
    header = Header.expand(%{kicker: "Monday", title: "Settings", show_back: true}, [], %{})

    assert text(header) =~ "Monday"
    assert text(header) =~ "Settings"
    assert find(header, :box, accessibility_label: "Back")
    refute find(Header.expand(%{title: "Settings"}, [], %{}), :box, accessibility_label: "Back")
    assert_renderable(header)
  end

  test "TransactionItem shows initials, vendor and the amount" do
    card = TransactionItem.expand(%{transaction: @java}, [], %{})

    assert text(card) =~ "JH"
    assert text(card) =~ "Java House"
    assert text(card) =~ "Ksh 870"
    assert_renderable(card)
  end

  test "TransactionItem keeps quiet about a pending expense, not a pending claim" do
    card = &TransactionItem.expand(%{transaction: &1}, [], %{})

    refute find(card.(@java), :row, accessibility_label: "Waiting for approval")

    claim = %{@java | type: "refund", method: "cash"}
    assert find(card.(claim), :row, accessibility_label: "Waiting for approval")
    assert text(card.(claim)) =~ "Refund · Meals & Entertainment"

    assert find(card.(%{@java | status: "approved"}), :row, accessibility_label: "Approved")
    assert text(card.(%{@java | status: "rejected"})) =~ "Rejected"
    assert text(card.(%{@java | status: "paid"})) =~ "Paid"
  end

  test "TransactionSheet shows the details, and no buttons once it's paid" do
    sheet = &TransactionSheet.expand(%{transaction: &1}, [], %{})

    pending = sheet.(%{@java | description: "Team lunch"})
    assert text(pending) =~ "Ksh 870.00"
    assert text(pending) =~ "Team lunch"
    assert text(pending) =~ "Waiting for approval"
    assert find(pending, :box, accessibility_label: "Edit")
    assert_renderable(pending)

    paid =
      sheet.(%{
        @java
        | type: "refund",
          status: "paid",
          method: "send_money",
          phone: "+254712345678"
      })

    assert text(paid) =~ "M-Pesa 0712 345 678"
    refute find(paid, :box, accessibility_label: "Edit")
  end

  test "a KRA receipt is tagged, on the card and in the sheet" do
    kra = %{
      @java
      | source: "etims",
        verify_url: "https://etims.kra.go.ke/x",
        seller_pin: "P051234567X"
    }

    assert find(TransactionItem.expand(%{transaction: kra}, [], %{}), :row,
             accessibility_label: "KRA receipt, not verified yet"
           )

    refute find(TransactionItem.expand(%{transaction: @java}, [], %{}), :row,
             accessibility_label: "KRA receipt, not verified yet"
           )

    sheet = TransactionSheet.expand(%{transaction: kra}, [], %{})
    assert text(sheet) =~ "Not verified yet"
    assert text(sheet) =~ "P051234567X"
    assert find(sheet, :box, accessibility_label: "Verify with KRA")

    verified =
      TransactionSheet.expand(
        %{transaction: %{kra | verified_at: ~U[2026-09-24 10:00:00Z]}},
        [],
        %{}
      )

    assert text(verified) =~ "Verified with KRA · 24 Sep 2026"
    assert find(verified, :box, accessibility_label: "View on KRA")
  end

  test "initials/1 copes with odd names" do
    assert TransactionItem.initials("naivas") == "N"
    assert TransactionItem.initials("Mama Oliech's Restaurant") == "MO"
    assert TransactionItem.initials("!!!") == "?"
  end

  test "ActionButton takes a weight so two can share a row" do
    assert ActionButton.button(nil, "Scan receipt", :take_photo, weight: 1).props.weight == 1
  end
end
