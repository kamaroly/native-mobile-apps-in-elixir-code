defmodule RisitiApp.ComponentsTest do
  use ExUnit.Case, async: true

  import Mob.ScreenCase, only: [text: 1, find: 3, assert_renderable: 1]

  alias RisitiApp.Components.{ActionButton, Header, TransactionItem}

  test "Header shows the kicker and title, and a back button only when asked" do
    header = Header.expand(%{kicker: "Monday", title: "Settings", show_back: true}, [], %{})

    assert text(header) =~ "Monday"
    assert text(header) =~ "Settings"
    assert find(header, :box, accessibility_label: "Back")
    refute find(Header.expand(%{title: "Settings"}, [], %{}), :box, accessibility_label: "Back")
    assert_renderable(header)
  end

  test "TransactionItem shows initials, vendor and the amount" do
    transaction = %{
      vendor: "Java House",
      category: "Meals & Entertainment",
      amount_cents: 87_000,
      date: ~D[2026-10-02]
    }

    card = TransactionItem.expand(%{transaction: transaction}, [], %{})

    assert text(card) =~ "JH"
    assert text(card) =~ "Java House"
    assert text(card) =~ "Ksh 870"
    assert_renderable(card)
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
