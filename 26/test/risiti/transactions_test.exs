defmodule Risiti.TransactionsTest do
  use Risiti.DataCase, async: false

  import Risiti.Fixtures

  alias Risiti.Expenses
  alias Risiti.Expenses.Transaction

  setup do
    business_team()
  end

  defp sync!(attrs, person),
    do: Expenses.sync_transaction!(phone_transaction(attrs), actor: person)

  describe "from the phone" do
    test "a new transaction waits for approval, and is its sender's", %{member: otieno} do
      t = sync!(%{}, otieno)

      assert t.status == :pending
      assert t.user_id == otieno.id
      assert t.pay_to == nil
    end

    test "sending it again updates it rather than making a copy", %{member: otieno} do
      attrs = phone_transaction()
      Expenses.sync_transaction!(attrs, actor: otieno)
      t = Expenses.sync_transaction!(%{attrs | "amount_cents" => 99_00}, actor: otieno)

      assert t.amount_cents == 99_00
      assert [_one] = Transaction.mine!(actor: otieno)
    end

    test "two people's phones can make up the same client_id", %{
      member: otieno,
      approver: achieng
    } do
      attrs = phone_transaction()
      mine = Expenses.sync_transaction!(attrs, actor: otieno)
      theirs = Expenses.sync_transaction!(attrs, actor: achieng)

      assert mine.id != theirs.id
    end

    test "who a claim pays follows from its type", %{member: otieno} do
      assert sync!(%{type: "refund", pay_to: "supplier"}, otieno).pay_to == :self
      assert sync!(%{type: "payment_request", method: "cash"}, otieno).pay_to == :supplier

      assert sync!(%{type: "payment_request", method: "cash", pay_to: "self"}, otieno).pay_to ==
               :self
    end

    test "each way of paying needs its details", %{member: otieno} do
      bad = [
        %{method: "send_money", phone: "0712345678"},
        %{method: "till", till_number: "12"},
        %{method: "paybill", paybill_number: "247247"},
        %{method: "carrier pigeon"}
      ]

      for attrs <- bad do
        assert {:error, %Ash.Error.Invalid{}} =
                 Expenses.sync_transaction(phone_transaction(attrs), actor: otieno)
      end

      assert sync!(
               %{method: "paybill", paybill_number: "247247", account_number: "0712345678"},
               otieno
             )

      assert sync!(%{method: "send_money", phone: "+254712345678"}, otieno)
    end

    test "a payment request must say how to pay", %{member: otieno} do
      assert {:error, %Ash.Error.Invalid{}} =
               Expenses.sync_transaction(phone_transaction(type: "payment_request"),
                 actor: otieno
               )
    end

    test "a client_id is required", %{member: otieno} do
      assert {:error, %Ash.Error.Invalid{}} =
               Expenses.sync_transaction(Map.delete(phone_transaction(), "client_id"),
                 actor: otieno
               )
    end
  end

  describe "deciding" do
    test "an approver approves, with a note", %{member: otieno, approver: achieng} do
      t = sync!(%{}, otieno)

      t = Transaction.approve!(t, "Thanks", actor: achieng)

      assert t.status == :approved
      assert t.decision_note == "Thanks"
      assert t.decided_by_id == achieng.id
      assert t.decided_at
    end

    test "someone without the permission can't", %{member: otieno, accountant: kamau} do
      t = sync!(%{}, otieno)

      assert {:error, %Ash.Error.Forbidden{}} = Transaction.approve(t, nil, actor: kamau)
      assert {:error, %Ash.Error.Forbidden{}} = Transaction.approve(t, nil, actor: otieno)
    end

    test "owners can do everything", %{member: otieno, owner: wanjiku} do
      t = sync!(%{type: "refund", method: "cash"}, otieno)

      t = Transaction.approve!(t, nil, actor: wanjiku)
      assert Transaction.mark_paid!(t, actor: wanjiku).status == :paid
    end

    test "a rejection needs a note", %{member: otieno, approver: achieng} do
      t = sync!(%{}, otieno)

      assert {:error, %Ash.Error.Invalid{}} = Transaction.reject(t, nil, actor: achieng)
      assert Transaction.reject!(t, "This is a duplicate", actor: achieng).status == :rejected
    end

    test "only a pending transaction can be decided", %{member: otieno, approver: achieng} do
      t = sync!(%{}, otieno) |> Transaction.approve!(nil, actor: achieng)

      assert {:error, %Ash.Error.Invalid{}} = Transaction.reject(t, "Too late", actor: achieng)
    end

    test "only an approved claim can be paid", %{member: otieno, approver: achieng} do
      expense = sync!(%{}, otieno) |> Transaction.approve!(nil, actor: achieng)
      refund = sync!(%{type: "refund", method: "cash"}, otieno)

      assert {:error, %Ash.Error.Invalid{}} = Transaction.mark_paid(expense, actor: achieng)
      assert {:error, %Ash.Error.Invalid{}} = Transaction.mark_paid(refund, actor: achieng)

      refund = Transaction.approve!(refund, nil, actor: achieng)

      assert %{status: :paid, paid_at: %DateTime{}} =
               Transaction.mark_paid!(refund, actor: achieng)
    end
  end

  describe "the phone owns the figures, the server owns the decisions" do
    test "changing a decided transaction's figures sends it back", %{
      member: otieno,
      approver: achieng
    } do
      attrs = phone_transaction()
      t = Expenses.sync_transaction!(attrs, actor: otieno)
      Transaction.approve!(t, "OK", actor: achieng)

      t = Expenses.sync_transaction!(%{attrs | "amount_cents" => 999_999}, actor: otieno)

      assert t.status == :pending
      assert t.decision_note == nil
      assert t.decided_by_id == nil
    end

    test "sending the same figures again keeps the decision", %{member: otieno, approver: achieng} do
      attrs = phone_transaction()
      t = Expenses.sync_transaction!(attrs, actor: otieno)
      Transaction.approve!(t, "OK", actor: achieng)

      t = Expenses.sync_transaction!(attrs, actor: otieno)

      assert t.status == :approved
      assert t.decision_note == "OK"
    end

    test "a paid transaction can't change", %{member: otieno, approver: achieng} do
      attrs = phone_transaction(type: "refund", method: "cash")
      t = Expenses.sync_transaction!(attrs, actor: otieno)
      t |> Transaction.approve!(nil, actor: achieng) |> Transaction.mark_paid!(actor: achieng)

      assert {:error, %Ash.Error.Invalid{}} =
               Expenses.sync_transaction(%{attrs | "amount_cents" => 1}, actor: otieno)
    end

    test "only its sender can change it", %{member: otieno, approver: achieng} do
      t = sync!(%{}, otieno)

      assert {:error, %Ash.Error.Forbidden{}} =
               Transaction.update_from_phone(t, %{vendor: "Mine now"}, actor: achieng)
    end

    test "it can be withdrawn until it's decided", %{member: otieno, approver: achieng} do
      assert :ok = sync!(%{}, otieno) |> Transaction.withdraw(actor: otieno)

      decided = sync!(%{}, otieno) |> Transaction.approve!(nil, actor: achieng)
      assert {:error, %Ash.Error.Invalid{}} = Transaction.withdraw(decided, actor: otieno)
    end
  end

  describe "a personal book" do
    test "is approved as it's saved, and again when it changes" do
      %{owner: njeri} = personal_book()
      attrs = phone_transaction()

      t = Expenses.sync_transaction!(attrs, actor: njeri)
      assert t.status == :approved
      assert t.decided_by_id == njeri.id

      t = Expenses.sync_transaction!(%{attrs | "amount_cents" => 1_00}, actor: njeri)
      assert t.status == :approved
    end
  end

  describe "who sees what" do
    setup %{member: otieno, approver: achieng, owner: wanjiku} do
      otieno_pending = sync!(%{vendor: "Otieno pending"}, otieno)
      sync!(%{vendor: "Otieno approved"}, otieno) |> Transaction.approve!(nil, actor: achieng)
      sync!(%{vendor: "Wanjiku's own"}, wanjiku) |> Transaction.approve!(nil, actor: wanjiku)
      %{otieno_pending: otieno_pending}
    end

    defp vendors(person),
      do: [actor: person] |> Transaction.list!() |> Enum.map(& &1.vendor) |> Enum.sort()

    test "people see their own", %{member: otieno} do
      assert vendors(otieno) == ["Otieno approved", "Otieno pending"]
    end

    test "approvers also see what's waiting on them", %{approver: achieng} do
      assert vendors(achieng) == ["Otieno pending"]
    end

    test "owners and accountants see everything", %{owner: wanjiku, accountant: kamau} do
      everything = ["Otieno approved", "Otieno pending", "Wanjiku's own"]
      assert vendors(wanjiku) == everything
      assert vendors(kamau) == everything
    end

    test "another team sees none of it", %{otieno_pending: t} do
      %{owner: njeri} = personal_book()

      assert vendors(njeri) == []
      assert {:error, %Ash.Error.Invalid{}} = Ash.get(Transaction, t.id, actor: njeri)
    end

    test "the sender and the decider load with it", %{approver: achieng, member: otieno} do
      [t] =
        Transaction.to_decide!(actor: achieng) |> Ash.load!([:user, :decided_by], actor: achieng)

      assert t.user.id == otieno.id
    end
  end

  test "every change is kept, with who made it", %{member: otieno, approver: achieng} do
    attrs = phone_transaction()
    t = Expenses.sync_transaction!(attrs, actor: otieno)
    Transaction.approve!(t, "OK", actor: achieng)
    Expenses.sync_transaction!(%{attrs | "amount_cents" => 1_00}, actor: otieno)

    versions =
      t
      |> Ash.load!(:paper_trail_versions, actor: otieno, authorize?: false)
      |> Map.fetch!(:paper_trail_versions)
      |> Enum.sort_by(& &1.version_inserted_at, DateTime)

    assert Enum.map(versions, &{&1.version_action_name, &1.user_id}) == [
             {:submit, otieno.id},
             {:approve, achieng.id},
             {:update_from_phone, otieno.id}
           ]

    assert %{"amount_cents" => 1_00, "status" => "pending"} = List.last(versions).changes
  end
end
