defmodule RisitiApp.Receipts.OcrParserTest do
  use ExUnit.Case, async: true

  alias RisitiApp.Receipts.OcrParser

  @today ~D[2026-10-06]
  @fixtures Path.expand("../../fixtures/receipts", __DIR__)

  # One file per receipt, as MobOcr hands the text over: one visual row
  # per line. Add a file and a line here whenever a real receipt reads wrong.
  @expected %{
    "naivas_etims.txt" => %{vendor: "Naivas Limited", date: ~D[2026-09-21], amount_cents: 245_000},
    "java_house.txt" => %{vendor: "Java House", date: ~D[2026-09-05], amount_cents: 165_000},
    # Read by ML Kit on a Galaxy A53 from a photo tilted by 3 degrees.
    "quickmart_phone.txt" => %{
      vendor: "Quickmart Limited",
      date: ~D[2026-10-04],
      amount_cents: 153_000
    },
    "fuel_station.txt" => %{vendor: "Rubis Energy", date: ~D[2026-09-19], amount_cents: 360_944}
  }

  for {file, expected} <- @expected do
    test "reads #{file}" do
      text = File.read!(Path.join(@fixtures, unquote(file)))
      assert OcrParser.parse(text, today: @today) == unquote(Macro.escape(expected))
    end
  end

  test "every fixture has an expected reading" do
    assert @fixtures |> File.ls!() |> Enum.sort() == @expected |> Map.keys() |> Enum.sort()
  end

  test "a strong label beats an earlier plain TOTAL" do
    text = """
    SHOP
    TOTAL  1,000.00
    TOTAL AMOUNT  1,160.00
    """

    assert %{amount_cents: 116_000} = OcrParser.parse(text, today: @today)
  end

  test "accepts ISO, two-digit-year and month-name dates" do
    assert %{date: ~D[2026-08-30]} = OcrParser.parse("X\nDATE 2026-08-30", today: @today)
    assert %{date: ~D[2026-08-30]} = OcrParser.parse("X\nDate: 30.08.26", today: @today)
    assert %{date: ~D[2026-08-30]} = OcrParser.parse("X\nAug 30, 2026", today: @today)
  end

  test "ignores impossible and future dates" do
    assert %{date: nil} = OcrParser.parse("X\nDATE 31/02/2026", today: @today)
    assert %{date: nil} = OcrParser.parse("X\nDATE 01/01/2030", today: @today)
  end

  test "keeps short all-caps words like KFC as they are" do
    assert %{vendor: "KFC Junction Mall"} = OcrParser.parse("KFC JUNCTION MALL", today: @today)
  end

  test "text with nothing recognisable gives all nils" do
    assert OcrParser.parse("", today: @today) == %{vendor: nil, date: nil, amount_cents: nil}
  end
end
