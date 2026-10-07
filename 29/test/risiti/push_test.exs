defmodule Risiti.PushTest do
  use Risiti.DataCase, async: false
  use Oban.Testing, repo: Risiti.Repo

  import Risiti.Fixtures

  alias Risiti.Accounts.PushDevice
  alias Risiti.Expenses
  alias Risiti.Expenses.Transaction

  setup do
    people = business_team()

    for {who, token} <- [owner: "owner-phone", approver: "approver-phone", member: "member-phone"] do
      PushDevice.register!(:android, token, actor: people[who])
    end

    people
  end

  # Runs the queued pushes here, and collects what the Log adapter "sent".
  defp pushes do
    Oban.drain_queue(queue: :push)
    collect([])
  end

  defp collect(acc) do
    receive do
      {:push, token, :android, payload} -> collect([{token, payload} | acc])
    after
      0 -> acc |> Enum.reverse() |> Enum.sort()
    end
  end

  test "a new transaction tells the approvers, not its sender", %{member: otieno} do
    t =
      Expenses.sync_transaction!(phone_transaction(vendor: "Rubis", amount_cents: 500_000),
        actor: otieno
      )

    assert [{"approver-phone", payload}, {"owner-phone", payload}] = pushes()

    assert payload == %{
             title: "New expense to approve",
             body: "#{otieno.name} · Rubis · Ksh 5,000",
             data: %{screen: "approvals", kind: "transaction", id: t.id}
           }
  end

  test "a decision tells the sender, with the note", %{member: otieno, approver: achieng} do
    t =
      Expenses.sync_transaction!(phone_transaction(type: "refund", method: "cash"), actor: otieno)

    pushes()

    Transaction.reject!(t, "This is a duplicate", actor: achieng)

    assert [{"member-phone", %{title: "Your refund was rejected", body: body}}] = pushes()
    assert body =~ "— This is a duplicate"
  end

  test "approving your own tells nobody", %{owner: wanjiku} do
    t = Expenses.sync_transaction!(phone_transaction(), actor: wanjiku)
    pushes()

    Transaction.approve!(t, nil, actor: wanjiku)
    assert pushes() == []
  end

  test "sending the same thing again tells nobody twice", %{member: otieno, approver: achieng} do
    attrs = phone_transaction()
    t = Expenses.sync_transaction!(attrs, actor: otieno)
    Transaction.approve!(t, nil, actor: achieng)
    Expenses.sync_transaction!(attrs, actor: otieno)
    Expenses.sync_transaction!(attrs, actor: otieno)

    titles = pushes() |> Enum.map(fn {_token, payload} -> payload.title end)

    assert Enum.sort(titles) == [
             "New expense to approve",
             "New expense to approve",
             "Your expense was approved"
           ]
  end

  test "a changed amount asks again", %{member: otieno, approver: achieng} do
    attrs = phone_transaction()
    t = Expenses.sync_transaction!(attrs, actor: otieno)
    Transaction.approve!(t, nil, actor: achieng)
    pushes()

    Expenses.sync_transaction!(%{attrs | "amount_cents" => 1_00}, actor: otieno)

    assert [{"approver-phone", %{title: "Expense changed, approve again"}}, {"owner-phone", _}] =
             pushes()
  end

  test "people with an email get it by email too", %{member: otieno, owner: wanjiku} do
    Ash.Seed.update!(wanjiku, %{email: "wanjiku@example.com"})

    Expenses.sync_transaction!(phone_transaction(), actor: otieno)
    Oban.drain_queue(queue: :push)

    assert_enqueued worker: Risiti.MailerWorker,
                    args: %{"to" => "wanjiku@example.com", "subject" => "New expense to approve"}
  end

  test "a token Firebase no longer knows is forgotten", %{member: otieno} do
    defmodule GoneToken do
      @behaviour Risiti.Push
      def send(_token, _platform, _payload), do: {:error, :device_token_not_found}
    end

    Application.put_env(:risiti, Risiti.Push, adapter: GoneToken)
    on_exit(fn -> Application.delete_env(:risiti, Risiti.Push) end)

    Expenses.sync_transaction!(phone_transaction(), actor: otieno)
    Oban.drain_queue(queue: :push)

    tokens = PushDevice |> Ash.read!(authorize?: false) |> Enum.map(& &1.token)
    assert tokens == ["member-phone"]
  end

  test "old sign-in codes are cleared out at night" do
    :ok = Risiti.Accounts.PhoneSignIn.request_code("0712345678")
    old = DateTime.add(DateTime.utc_now(), -2, :day)
    Repo.query!("UPDATE phone_codes SET inserted_at = $1", [old])
    :ok = Risiti.Accounts.PhoneSignIn.request_code("0712345679")

    assert :ok = perform_job(Risiti.Accounts.ForgetOldCodes, %{})
    assert [%{phone: "+254712345679"}] = Ash.read!(Risiti.Accounts.PhoneCode, authorize?: false)
  end
end
