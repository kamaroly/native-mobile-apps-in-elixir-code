defmodule RisitiApp.Components.TransactionItem do
  @moduledoc """
  A transaction as a list card: a tinted badge with the vendor's initials, the
  vendor over its category, and the amount over the date.

      <TransactionItem transaction={transaction} />
  """

  import Mob.Sigil

  alias RisitiApp.{Theme, Transactions}

  def expand(props, _children, _ctx) do
    transaction = Map.fetch!(props, :transaction)
    group = Transactions.group(transaction.category)

    ~MOB"""
    <Column fill_width={true} padding_bottom={10}>
      <Box
        background={:surface}
        border_color={:border}
        border_width={1}
        corner_radius={20}
        padding={12}
        fill_width={true}
      >
        <Row fill_width={true} align={:center} gap={12}>
          <Box
            width={46}
            height={46}
            corner_radius={14}
            background={Theme.color(:"#{group}_tint")}
            align={:center}
          >
            <Text
              text={initials(transaction.vendor)}
              text_color={Theme.color(group)}
              text_size={17}
              font_weight="bold"
            />
          </Box>
          <Column weight={1}>
            <Text
              text={transaction.vendor}
              text_size={15}
              font_weight="semibold"
              text_color={:on_surface}
              max_lines={1}
            />
            <Text text={transaction.category} text_size={12} text_color={:muted} max_lines={1} />
          </Column>
          <Column>
            <Text
              text={Transactions.format_short(transaction.amount_cents)}
              text_size={15}
              font_weight="bold"
              text_color={:on_surface}
            />
            <Text
              text={Calendar.strftime(transaction.date, "%d %b")}
              text_size={11}
              text_color={:muted}
            />
          </Column>
        </Row>
      </Box>
    </Column>
    """
  end

  @doc "Up to two capital letters: \"Java House\" -> \"JH\"."
  def initials(nil), do: "?"

  def initials(name) do
    name
    |> String.split(~r/[^[:alnum:]]+/u, trim: true)
    |> Enum.map_join(&String.first/1)
    |> String.slice(0, 2)
    |> String.upcase()
    |> case do
      "" -> "?"
      initials -> initials
    end
  end
end
