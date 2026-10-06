defmodule RisitiApp.Components.TransactionItem do
  @moduledoc """
  How a transaction is shown: as a list card (`expand/3`) and as the body of
  its details sheet (`details/1`).

  The card is a tinted badge with the vendor's initials (or the receipt
  photo), the vendor over what it was for (tagged KRA when it's a KRA
  receipt), and the amount over the date.
  Where it stands is kept small: a tick beside the date (amber while a
  claim waits, green once approved) and a slim pill for paid and rejected.
  An expense nobody has looked at yet shows nothing.

      <TransactionItem transaction={transaction} />
  """

  import Mob.Sigil

  alias RisitiApp.{Theme, Transactions}
  alias RisitiApp.Components.KraBadge
  alias RisitiApp.Receipts.Photos
  alias RisitiApp.Transactions.Transaction

  def expand(props, _children, _ctx) do
    transaction = Map.fetch!(props, :transaction)

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
          {badge(transaction)}
          <Column weight={1}>
            <Text
              text={transaction.vendor}
              text_size={15}
              font_weight="semibold"
              text_color={:on_surface}
              max_lines={1}
            />
            <Row fill_width={true} align={:center}>
              {KraBadge.badge(transaction)}
              <Text
                text={subtitle(transaction)}
                text_size={12}
                text_color={:muted}
                max_lines={1}
                weight={1}
              />
            </Row>
          </Column>
          <Column>
            <Text
              text={Transactions.format_short(transaction.amount_cents)}
              text_size={15}
              font_weight="bold"
              text_color={:on_surface}
            />
            <Row align={:center}>
              {status_icon(transaction)}
              <Text
                text={Calendar.strftime(transaction.date, "%d %b")}
                text_size={11}
                text_color={:muted}
              />
            </Row>
            {status_tag(transaction)}
          </Column>
        </Row>
      </Box>
    </Column>
    """
  end

  # The receipt photo when it's on the phone, otherwise the vendor's initials
  # on the spending group's tint.
  defp badge(%{photo_path: photo} = transaction) when is_binary(photo) do
    if Photos.exists?(photo) do
      ~MOB"""
      <Image src={Photos.path(photo)} width={46} height={46} corner_radius={14} content_mode={:fill} />
      """
    else
      initials_badge(transaction)
    end
  end

  defp badge(transaction), do: initials_badge(transaction)

  defp initials_badge(transaction) do
    group = Transactions.group(transaction.category)

    ~MOB"""
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
    """
  end

  @doc """
  What it was for: the type of a claim, the description, the category.

      iex> RisitiApp.Components.TransactionItem.subtitle(%{
      ...>   type: "refund", description: "Team lunch", category: "Meals & Entertainment"
      ...> })
      "Refund · Team lunch · Meals & Entertainment"
  """
  def subtitle(transaction) do
    [claim_label(transaction), Map.get(transaction, :description), transaction.category]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp claim_label(%{type: type}) when type in ["refund", "payment_request"],
    do: Transactions.type_label(type)

  defp claim_label(_expense), do: nil

  # A tick beside the date: amber while a claim waits, green once approved.
  # An expense waiting for approval is the normal case, so it shows nothing.
  defp status_icon(%{status: "pending"} = transaction) do
    if Transaction.claim?(transaction),
      do: tick(Theme.color(:pending), "Waiting for approval"),
      else: []
  end

  defp status_icon(%{status: "approved"}), do: tick(:secondary, "Approved")
  defp status_icon(_transaction), do: []

  defp tick(color, label) do
    ~MOB"""
    <Row align={:center} accessibility_label={label}>
      <Icon name="check" text_size={13} text_color={color} />
      <Spacer size={3} />
    </Row>
    """
  end

  # Paid and rejected are final, so they get words, not just a colour.
  defp status_tag(%{status: status}) when status in ["paid", "rejected"] do
    {background, text_color} =
      if status == "paid", do: {:secondary, :on_secondary}, else: {:error, :on_error}

    ~MOB"""
    <Column padding_top={3}>
      <Row background={background} corner_radius={:radius_pill} padding_left={6} padding_right={6}>
        <Text
          text={Transactions.status_label(status)}
          text_size={10}
          font_weight="semibold"
          text_color={text_color}
        />
      </Row>
    </Column>
    """
  end

  defp status_tag(_transaction), do: []

  @doc """
  The body of the details sheet: the type and amount in a box, then a row
  for each detail the transaction has. Empty ones are left out.
  """
  def details(transaction) do
    ~MOB"""
    <Column fill_width={true}>
      <Box
        background={:surface}
        border_color={:border}
        border_width={1}
        corner_radius={16}
        padding={14}
        fill_width={true}
      >
        <Column fill_width={true}>
          <Text text={Transactions.type_label(transaction.type)} text_size={12} text_color={:muted} />
          <Text
            text={Transactions.format_amount(transaction.amount_cents)}
            text_size={22}
            font_weight="bold"
            text_color={:on_surface}
          />
        </Column>
      </Box>
      {detail_row("Pay with", Transactions.pay_details(transaction))}
      {detail_row("Pay to", pay_to_label(transaction.pay_to))}
      {detail_row("Date", Calendar.strftime(transaction.date, "%a, %d %b %Y"))}
      {detail_row("Category", transaction.category)}
      {detail_row("Description", transaction.description)}
      {detail_row("Seller KRA PIN", Map.get(transaction, :seller_pin))}
      {detail_row("Receipt / invoice no.", Map.get(transaction, :invoice_number))}
      {detail_row("Approver's note", transaction.decision_note)}
    </Column>
    """
  end

  defp pay_to_label("self"), do: "You"
  defp pay_to_label("supplier"), do: "A supplier"
  defp pay_to_label(_nobody), do: nil

  defp detail_row(_label, value) when value in [nil, ""], do: []

  defp detail_row(label, value) do
    ~MOB"""
    <Column fill_width={true} padding_top={10}>
      <Text text={label} text_size={12} text_color={:muted} />
      <Text text={value} text_size={14} text_color={:on_background} max_lines={3} />
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
