defmodule RisitiWeb.TransactionsLive do
  @moduledoc """
  The transactions the signed-in person may see (their own, or the whole
  team's for owners and accountants: the transaction's policies decide),
  newest first, optionally one status. Accountants export from here.
  """

  use RisitiWeb, :live_view

  alias Risiti.Accounts.Permissions
  alias Risiti.Expenses
  alias Risiti.Expenses.{Export, Transaction}

  @statuses ~w(pending approved rejected paid)

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    if connected?(socket), do: RisitiWeb.Endpoint.subscribe("transactions:#{user.current_team}")

    today = Expenses.today()

    socket
    |> assign(
      status: nil,
      can_export: Permissions.can?(user, "transactions:export_transactions"),
      export:
        to_form(%{
          "from" => Date.to_iso8601(Date.beginning_of_month(today)),
          "to" => Date.to_iso8601(today)
        })
    )
    |> load()
    |> then(&{:ok, &1})
  end

  def handle_event("filter", %{"status" => status}, socket) do
    status = if status in @statuses, do: String.to_existing_atom(status)
    {:noreply, socket |> assign(status: status) |> load()}
  end

  def handle_info(%Phoenix.Socket.Broadcast{}, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    input = if socket.assigns.status, do: %{status: socket.assigns.status}, else: %{}
    transactions = Transaction.list!(input, actor: socket.assigns.current_user, load: [:user])
    assign(socket, transactions: transactions)
  end

  def render(assigns) do
    assigns = assign(assigns, statuses: @statuses, formats: Export.formats())

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} can_decide={@can_decide}>
      <.header>
        Transactions
        <:actions>
          <.link navigate={~p"/transactions/new"} class="btn btn-primary">New transaction</.link>
        </:actions>
      </.header>

      <form id="filter" phx-change="filter">
        <select name="status" class="select select-bordered">
          <option value="">Every status</option>
          <option :for={s <- @statuses} value={s} selected={@status == String.to_atom(s)}>
            {String.capitalize(s)}
          </option>
        </select>
      </form>

      <.table id="transactions" rows={@transactions}>
        <:col :let={t} label="Date">{t.date}</:col>
        <:col :let={t} label="Vendor">{t.vendor}</:col>
        <:col :let={t} label="Category">{t.category}</:col>
        <:col :let={t} label="From">{t.user.name || t.user.phone}</:col>
        <:col :let={t} label="Status">{t.status}</:col>
        <:col :let={t} label="Amount">{Expenses.format_amount(t.amount_cents)}</:col>
      </.table>

      <section :if={@can_export} id="export" class="card bg-base-200 p-5">
        <h2 class="font-semibold">Export for accounting</h2>
        <p class="text-sm opacity-70">Approved and paid transactions dated in the period.</p>
        <.form
          for={@export}
          action={~p"/transactions/export"}
          method="get"
          class="flex flex-wrap items-end gap-3"
        >
          <.input field={@export[:from]} type="date" label="From" />
          <.input field={@export[:to]} type="date" label="To" />
          <.input
            name="format"
            type="select"
            label="Format"
            value="quickbooks"
            options={Enum.map(@formats, fn {id, name} -> {name, id} end)}
          />
          <.input name="unexported_only" type="checkbox" label="Only ones not exported before" />
          <.button>Download</.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
