defmodule RisitiWeb.ApprovalsLive do
  @moduledoc """
  What waits on an approver, oldest first: transactions to approve or
  reject (a rejection needs a note, so the person knows what to fix), and
  approved refunds and payment requests to mark paid. Updates live as
  phones send more.
  """

  use RisitiWeb, :live_view

  alias Risiti.Accounts.Permissions
  alias Risiti.Expenses
  alias Risiti.Expenses.Transaction

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    can_approve = Permissions.can?(user, "transactions:approve_transactions")
    can_pay = Permissions.can?(user, "transactions:mark_transactions_paid")

    if can_approve or can_pay do
      if connected?(socket), do: RisitiWeb.Endpoint.subscribe("transactions:#{user.current_team}")

      socket
      |> assign(can_approve: can_approve, can_pay: can_pay, notes: %{}, errors: %{})
      |> load()
      |> then(&{:ok, &1})
    else
      {:ok,
       socket
       |> put_flash(:error, "You can't approve transactions")
       |> redirect(to: ~p"/transactions")}
    end
  end

  def handle_event("note", %{"transaction_id" => id, "note" => note}, socket),
    do: {:noreply, assign(socket, notes: Map.put(socket.assigns.notes, id, note))}

  def handle_event(decision, %{"id" => id}, socket) when decision in ~w(approve reject pay) do
    user = socket.assigns.current_user
    note = socket.assigns.notes |> Map.get(id, "") |> String.trim()

    if decision == "reject" and note == "" do
      {:noreply,
       assign(socket,
         errors: Map.put(socket.assigns.errors, id, "Say why, so they know what to fix")
       )}
    else
      with {:ok, t} <- Ash.get(Transaction, id, actor: user),
           {:ok, _decided} <- decide(t, decision, note, user) do
        socket
        |> put_flash(:info, done(decision))
        |> assign(
          notes: Map.delete(socket.assigns.notes, id),
          errors: Map.delete(socket.assigns.errors, id)
        )
        |> load()
        |> then(&{:noreply, &1})
      else
        _error -> {:noreply, socket |> put_flash(:error, "Couldn't save the decision") |> load()}
      end
    end
  end

  # Another approver, or a phone, changed something in this team.
  def handle_info(%Phoenix.Socket.Broadcast{}, socket), do: {:noreply, load(socket)}

  defp decide(t, "approve", "", user), do: Transaction.approve(t, nil, actor: user)
  defp decide(t, "approve", note, user), do: Transaction.approve(t, note, actor: user)
  defp decide(t, "reject", note, user), do: Transaction.reject(t, note, actor: user)
  defp decide(t, "pay", _note, user), do: Transaction.mark_paid(t, actor: user)

  defp done("approve"), do: "Approved"
  defp done("reject"), do: "Rejected"
  defp done("pay"), do: "Marked as paid"

  defp load(socket) do
    user = socket.assigns.current_user
    assign(socket, transactions: Transaction.to_decide!(actor: user, load: [:user, :attachments]))
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} can_decide={@can_decide}>
      <.header>Approvals</.header>

      <p :if={@transactions == []} id="nothing-waiting" class="opacity-70">
        Nothing waiting. New expenses, refunds and payment requests appear here.
      </p>

      <section
        :for={t <- @transactions}
        id={"transaction-#{t.id}"}
        class="card bg-base-200 p-5 space-y-2"
      >
        <div class="flex flex-wrap items-baseline justify-between gap-2">
          <h2 class="text-lg font-semibold">{t.vendor}</h2>
          <p class="text-xl font-bold">{Expenses.format_amount(t.amount_cents)}</p>
        </div>
        <p class="text-sm opacity-70">
          {t.date} · {t.category} · {type_label(t.type)} · {t.status} · from {t.user.name ||
            t.user.phone}
        </p>
        <p :if={t.description}>{t.description}</p>
        <p :if={t.photo_file}>
          <a href={~p"/transactions/#{t.id}/photo"} target="_blank" class="link">Receipt photo</a>
        </p>
        <p :for={a <- t.attachments}>
          <a href={~p"/attachments/#{a.id}"} target="_blank" class="link">{a.name}</a>
        </p>

        <form
          :if={t.status == :pending and @can_approve}
          id={"note-#{t.id}"}
          phx-change="note"
          class="flex flex-wrap gap-2"
        >
          <input type="hidden" name="transaction_id" value={t.id} />
          <input
            name="note"
            value={Map.get(@notes, t.id, "")}
            placeholder="Note (needed to reject)"
            class="input input-bordered flex-1"
          />
          <button
            type="button"
            phx-click="reject"
            phx-value-id={t.id}
            class="btn btn-outline btn-error"
          >
            Reject
          </button>
          <button type="button" phx-click="approve" phx-value-id={t.id} class="btn btn-success">
            Approve
          </button>
        </form>
        <p :if={@errors[t.id]} class="text-error text-sm">{@errors[t.id]}</p>

        <button
          :if={t.status == :approved and @can_pay}
          phx-click="pay"
          phx-value-id={t.id}
          class="btn"
        >
          Mark as paid
        </button>
      </section>
    </Layouts.app>
    """
  end

  defp type_label("refund"), do: "Refund"
  defp type_label("payment_request"), do: "Payment request"
  defp type_label(_expense), do: "Expense"
end
