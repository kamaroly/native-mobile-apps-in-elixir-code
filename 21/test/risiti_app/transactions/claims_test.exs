defmodule RisitiApp.Transactions.ClaimsTest do
  use ExUnit.Case, async: false

  import RisitiApp.ScreenHelpers

  alias RisitiApp.Transactions

  setup :checkout_repo

  doctest RisitiApp.Transactions.Attachments

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end

  defp payment(attrs) do
    Map.merge(
      %{
        type: "payment_request",
        date: ~D[2026-10-05],
        vendor: "Kamau Hardware",
        amount_cents: 1_250_000,
        category: "Office Supplies"
      },
      attrs
    )
  end

  defp refund do
    {:ok, refund} =
      Transactions.request_refund(insert_transaction(), %{
        method: "send_money",
        phone: "0712 345 678"
      })

    refund
  end

  describe "client_id" do
    test "every new transaction gets its own, for life" do
      a = insert_transaction()
      b = insert_transaction()

      assert {:ok, _} = Ecto.UUID.cast(a.client_id)
      assert a.client_id != b.client_id

      {:ok, edited} = Transactions.update_transaction(a, %{vendor: "Naivas Westlands"})
      assert edited.client_id == a.client_id
    end
  end

  describe "claims" do
    test "an expense pays nobody; a refund pays the person, by phone" do
      assert insert_transaction().pay_to == nil

      refund = refund()
      assert refund.type == "refund"
      assert refund.pay_to == "self"
      assert refund.phone == "+254712345678"
    end

    test "a payment request pays a supplier unless it's an advance" do
      {:ok, supplier} = Transactions.create_transaction(payment(%{method: "cash"}))

      {:ok, advance} =
        Transactions.create_transaction(payment(%{method: "cash", pay_to: "self"}))

      assert supplier.pay_to == "supplier"
      assert advance.pay_to == "self"
    end

    test "a claim must say how to pay" do
      {:error, changeset} = Transactions.create_transaction(payment(%{}))
      assert %{method: ["choose how to pay"]} = errors_on(changeset)
    end

    test "each way of paying asks for its own details" do
      {:error, till} =
        Transactions.create_transaction(payment(%{method: "till", till_number: "12"}))

      assert %{till_number: ["is 5 to 7 digits"]} = errors_on(till)

      {:error, paybill} =
        Transactions.create_transaction(payment(%{method: "paybill", paybill_number: "247247"}))

      assert %{account_number: ["enter the account number"]} = errors_on(paybill)

      {:error, phone} =
        Transactions.create_transaction(payment(%{method: "send_money", phone: "12345"}))

      assert %{phone: ["is not a valid Kenyan mobile number"]} = errors_on(phone)

      assert {:ok, _} =
               Transactions.create_transaction(
                 payment(%{
                   method: "paybill",
                   paybill_number: "247247",
                   account_number: "INV-204"
                 })
               )
    end

    test "only an expense can become a refund" do
      assert Transactions.request_refund(refund(), %{}) == {:error, :not_expense}
    end

    test "a pending refund can be taken back; a decided one can't" do
      {:ok, expense} = Transactions.cancel_refund(refund())
      assert expense.type == "expense"
      assert expense.method == nil
      assert expense.pay_to == nil

      {:ok, approved} = Transactions.decide(refund(), "approved")
      assert Transactions.cancel_refund(approved) == {:error, :not_pending}
    end
  end

  describe "status" do
    test "changing the figures of a decided transaction sends it back to pending" do
      {:ok, approved} = Transactions.decide(insert_transaction(), "approved", "Thanks")

      {:ok, untouched} = Transactions.update_transaction(approved, %{vendor: approved.vendor})
      assert untouched.status == "approved"

      {:ok, changed} = Transactions.update_transaction(approved, %{amount_cents: 99_900})
      assert changed.status == "pending"
      assert changed.decision_note == nil
      assert changed.decided_at == nil
    end

    test "a paid transaction can't be changed" do
      {:ok, approved} = Transactions.decide(refund(), "approved")
      {:ok, paid} = Transactions.decide(approved, "paid")

      assert paid.paid_at
      assert Transactions.update_transaction(paid, %{amount_cents: 1}) == {:error, :paid}
    end

    test "rejected spending doesn't count in the month's total" do
      insert_transaction(amount_cents: 100_000)

      {:ok, _} =
        Transactions.decide(insert_transaction(amount_cents: 50_000), "rejected", "Personal")

      assert Transactions.summary().total == 100_000
    end
  end
end
