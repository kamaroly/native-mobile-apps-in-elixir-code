defmodule Risiti.PushWorker do
  @moduledoc """
  Tells the right people that a transaction changed, in the background
  (queued by `Risiti.Expenses.PushNotifier`), by push and by email.

    * Something new to decide (`transaction_submitted`,
      `transaction_resubmitted`) goes to the team's members who may approve
      it, except whoever sent it.
    * A decision (`transaction_approved`, `transaction_rejected`,
      `transaction_paid`) goes to the person who sent it, unless they made
      it themselves.

  The push also makes the phone sync, so its lists catch up without a tap.
  A job is unique per event and `version`, so a resend never notifies twice.
  """

  use Oban.Worker,
    queue: :push,
    max_attempts: 3,
    unique: [period: :infinity, keys: [:event, :id, :version]]

  alias Risiti.Accounts
  alias Risiti.Accounts.Permissions
  alias Risiti.Expenses.Transaction

  @doc "Queues `event` for `transaction`, which `actor_id` caused."
  @spec enqueue(String.t(), Transaction.t(), String.t(), Ecto.UUID.t() | nil, term()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(event, transaction, tenant, actor_id, version) do
    %{
      "event" => event,
      "id" => transaction.id,
      "tenant" => tenant,
      "actor_id" => actor_id,
      "version" => version && to_string(version)
    }
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event" => event, "id" => id, "tenant" => tenant} = args}) do
    case Ash.get(Transaction, id, tenant: tenant, load: [:user], authorize?: false) do
      {:ok, transaction} ->
        {user_ids, payload} = message(event, transaction, tenant, args["actor_id"])
        Risiti.Push.notify(user_ids, payload)
        Risiti.Email.notify(user_ids, payload.title, payload.body, web_path(payload))
        :ok

      # Withdrawn since: nothing to say.
      {:error, _} ->
        :ok
    end
  end

  # ── Who hears, and what ───────────────────────────────────────────────────

  defp message("transaction_submitted", t, tenant, actor_id) do
    {deciders(tenant, actor_id),
     payload("New #{label(t)} to approve", summary(t, person(t.user)), "approvals", t)}
  end

  defp message("transaction_resubmitted", t, tenant, actor_id) do
    {deciders(tenant, actor_id),
     payload(
       "#{String.capitalize(label(t))} changed, approve again",
       summary(t, person(t.user)),
       "approvals",
       t
     )}
  end

  defp message("transaction_paid", t, _tenant, actor_id) do
    {sender(t, actor_id),
     payload("Your #{label(t)} has been paid", summary(t, nil), "transactions", t)}
  end

  defp message("transaction_" <> decision, t, _tenant, actor_id) do
    {sender(t, actor_id),
     payload(
       "Your #{label(t)} was #{decision}",
       with_note(summary(t, nil), t.decision_note),
       "transactions",
       t
     )}
  end

  # The push carries what to show and which screen to open, not the transaction.
  defp payload(title, body, screen, t),
    do: %{title: title, body: body, data: %{screen: screen, kind: "transaction", id: t.id}}

  defp web_path(%{data: %{screen: "approvals"}}), do: "/approvals"
  defp web_path(%{data: %{id: id}}), do: "/transactions/#{id}"

  defp label(%{type: "refund"}), do: "refund"
  defp label(%{type: "payment_request"}), do: "payment request"
  defp label(_expense), do: "expense"

  defp summary(t, who),
    do: [who, t.vendor, money(t.amount_cents)] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")

  defp sender(%{user_id: user_id}, user_id), do: []
  defp sender(%{user_id: user_id}, _actor_id), do: [user_id]

  # The team's members who may approve (owners may do everything).
  defp deciders(tenant, actor_id) do
    case Accounts.team_for_tenant(tenant, load: [:users], authorize?: false) do
      {:ok, %{users: users}} ->
        for user <- users,
            user.id != actor_id,
            Permissions.can?(%{user | current_team: tenant}, "transactions:approve_transactions"),
            do: user.id

      _ ->
        []
    end
  end

  defp person(%{name: name}) when is_binary(name) and name != "", do: name
  defp person(%{phone: phone}) when is_binary(phone), do: phone
  defp person(_user), do: "Someone"

  defp with_note(text, note) when is_binary(note) and note != "", do: "#{text} — #{note}"
  defp with_note(text, _note), do: text

  # Ksh 12,500, or Ksh 1,250.50 when there are cents.
  defp money(cents) do
    shillings = cents |> div(100) |> Integer.to_string() |> group_thousands()

    case rem(cents, 100) do
      0 -> "Ksh #{shillings}"
      rest -> "Ksh #{shillings}.#{String.pad_leading("#{rest}", 2, "0")}"
    end
  end

  defp group_thousands(digits),
    do:
      digits |> String.reverse() |> String.replace(~r/(\d{3})(?=\d)/, "\\1,") |> String.reverse()
end
