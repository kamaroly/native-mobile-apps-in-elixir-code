defmodule RisitiApp.Components.TransactionSheet do
  @moduledoc """
  A bottom sheet with everything about one transaction, opened by tapping it
  in the list.

      <TransactionSheet :if={@selected} transaction={@selected} />

  Sends `{:tap, :edit_transaction}`, `{:tap, :delete_transaction}` and
  `{:tap, :close_transaction}`, or `{:dismiss, :close_transaction}` when
  it's swiped away.
  """

  import Mob.Sigil

  alias RisitiApp.Components.{ActionButton, Header, TransactionItem}
  alias RisitiApp.Transactions.Transaction

  def expand(props, _children, _ctx) do
    transaction = Map.fetch!(props, :transaction)

    ~MOB"""
    <Sheet
      id={"transaction-#{transaction.id}"}
      detents={[:content]}
      background={:background}
      corner_radius={28}
      on_dismiss={{self(), :close_transaction}}
    >
      <Column fill_width={true} padding={20}>
        <Row fill_width={true} align={:center}>
          <Text
            text={transaction.vendor}
            text_size={20}
            font_weight="bold"
            text_color={:on_background}
            max_lines={2}
            weight={1}
          />
          <Spacer size={12} />
          {Header.icon_button("close", "Close", {self(), :close_transaction})}
        </Row>
        <Spacer size={14} />
        {TransactionItem.details(transaction)}
        {status_line(transaction)}
        <Spacer size={16} />
        {edit_buttons(transaction)}
      </Column>
    </Sheet>
    """
  end

  # Where the decision stands, in words.
  defp status_line(transaction) do
    {icon, color, text} = status(transaction)

    ~MOB"""
    <Row fill_width={true} align={:center} padding_top={12}>
      <Icon name={icon} text_size={18} text_color={color} />
      <Spacer size={8} />
      <Text text={text} text_size={13} font_weight="medium" text_color={color} weight={1} />
    </Row>
    """
  end

  defp status(%{status: "paid", paid_at: at}), do: {"check", :secondary, "Paid#{on(at)}"}

  defp status(%{status: "approved", decided_at: at} = transaction) do
    waiting = if Transaction.claim?(transaction), do: " · waiting to be paid", else: ""
    {"check", :secondary, "Approved#{on(at)}#{waiting}"}
  end

  defp status(%{status: "rejected", decided_at: at}), do: {"close", :error, "Rejected#{on(at)}"}
  defp status(_pending), do: {"info", :muted, "Waiting for approval"}

  defp on(%DateTime{} = at), do: " · #{Calendar.strftime(at, "%d %b")}"
  defp on(nil), do: ""

  # A paid transaction is settled: nothing left to change.
  defp edit_buttons(%{status: "paid"}), do: []

  defp edit_buttons(_transaction) do
    ~MOB"""
    <Row fill_width={true} gap={8}>
      {ActionButton.button("edit", "Edit", :edit_transaction, weight: 1)}
      {ActionButton.button("trash", "Delete", :delete_transaction, style: :danger, weight: 1)}
    </Row>
    """
  end
end
