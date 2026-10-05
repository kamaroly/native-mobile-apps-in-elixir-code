defmodule RisitiApp.Screens.ReceiptsScreen do
  use Mob.Screen

  alias RisitiApp.{Theme, Transactions}

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    socket =
      socket
      |> Mob.Socket.assign(:group, :all)
      |> Mob.List.put_renderer(:receipts, &receipt_row/1)
      |> load_receipts()

    {:ok, socket}
  end

  defp load_receipts(socket) do
    Mob.Socket.assign(socket,
      items: Transactions.list_transactions(socket.assigns.group),
      summary: Transactions.summary()
    )
  end

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Column background={:background} fill_width={true} fill_height={true}>
      <Row padding_left={22} padding_right={22} padding_top={12} padding_bottom={14}>
        <Column weight={1}>
          <Text
            text={Calendar.strftime(Transactions.today(), "%A, %d %b")}
            text_size={13}
            text_color={:muted}
          />
          <Text text="Your expenses" text_size={26} font_weight="bold" text_color={:on_background} />
        </Column>
        <Button
          text="Settings"
          width={120}
          background={:surface}
          text_color={:on_surface}
          padding={:space_sm}
          on_tap={{self(), :open_settings}}
        />
      </Row>
      <Column padding_left={18} padding_right={18} padding_bottom={14}>
        {spend_card(@summary)}
      </Column>
      {chips(@group, @summary.count)}
      <Spacer size={10} />
      <List id={:receipts} items={@items} weight={1} padding_left={18} padding_right={18} />
      <Row padding={14} gap={8}>
        <Button
          text="Scan receipt"
          weight={1}
          background={:primary}
          text_color={:on_primary}
          padding={:space_sm}
          on_tap={{self(), :take_photo}}
        />
        <Button
          text="Add"
          width={96}
          background={:surface}
          text_color={:on_surface}
          padding={:space_sm}
          on_tap={{self(), :add_manual}}
        />
      </Row>
    </Column>
    """
  end

  defp spend_card(summary) do
    ~MOB"""
    <Box
      background={Theme.color(:spend_card)}
      corner_radius={:radius_lg}
      padding={20}
      fill_width={true}
    >
      <Column>
        <Text text="Spent this month" text_size={13} text_color={Theme.color(:spend_muted)} />
        <Spacer size={10} />
        <Text
          text={Transactions.format_short(summary.total)}
          text_size={36}
          font_weight="bold"
          letter_spacing={-1.8}
          text_color={Theme.color(:spend_text)}
        />
        <Spacer size={14} />
        <Row gap={8}>
          {Enum.map(Transactions.groups(), &split_cell(&1, summary.by_group[&1]))}
        </Row>
      </Column>
    </Box>
    """
  end

  # One of the three boxes under the total: a coloured dot and a label over
  # an amount.
  defp split_cell(group, cents) do
    ~MOB"""
    <Box weight={1} background={Theme.color(:spend_chip)} corner_radius={14} padding={10}>
      <Column>
        <Row align={:center}>
          <Box width={7} height={7} corner_radius={4} background={Theme.color(group)} />
          <Spacer size={5} />
          <Text
            text={Transactions.group_label(group)}
            text_size={11}
            text_color={Theme.color(:spend_muted)}
          />
        </Row>
        <Spacer size={3} />
        <Text
          text={Transactions.format_short(cents)}
          text_size={13}
          font_weight="semibold"
          text_color={Theme.color(:spend_text)}
        />
      </Column>
    </Box>
    """
  end

  # All / Food / Fuel / Other. The strip scrolls sideways in case a large
  # font size pushes the last pill off the screen.
  defp chips(active, count) do
    pills =
      [
        {:all, "All · #{count}"}
        | Enum.map(Transactions.groups(), &{&1, Transactions.group_label(&1)})
      ]
      |> Enum.map(fn {group, label} -> chip(group, label, group == active) end)

    ~MOB"""
    <Scroll axis="horizontal" fill_width={true}>
      <Row padding_left={18} padding_right={18} gap={8}>
        {pills}
      </Row>
    </Scroll>
    """
  end

  defp chip(group, label, active?) do
    {background, text_color} =
      if active?, do: {:on_background, :background}, else: {:surface, :on_surface}

    ~MOB"""
    <Row
      background={background}
      border_color={if(active?, do: :on_background, else: :border)}
      border_width={1}
      corner_radius={:radius_pill}
      padding_left={12}
      padding_right={12}
      padding_top={7}
      padding_bottom={7}
      on_tap={{self(), {:group, group}}}
    >
      <Text text={label} text_size={13} font_weight="medium" text_color={text_color} />
    </Row>
    """
  end

  # One receipt in the list: vendor over category on the left, amount over
  # date on the right.
  defp receipt_row(receipt) do
    ~MOB"""
    <Row padding_top={12} padding_bottom={12} gap={12}>
      <Column weight={1}>
        <Text
          text={receipt.vendor}
          text_size={15}
          font_weight="semibold"
          text_color={:on_background}
          max_lines={1}
        />
        <Text text={receipt.category} text_size={12} text_color={:muted} max_lines={1} />
      </Column>
      <Column>
        <Text
          text={Transactions.format_short(receipt.amount_cents)}
          text_size={15}
          font_weight="bold"
          text_color={:on_background}
        />
        <Text text={Calendar.strftime(receipt.date, "%d %b")} text_size={11} text_color={:muted} />
      </Column>
    </Row>
    """
  end

  @impl Mob.Screen
  def handle_info({:select, :receipts, index}, socket) do
    receipt = Enum.at(socket.assigns.items, index)

    {:noreply,
     Mob.Socket.push_screen(socket, RisitiApp.Screens.ReceiptFormScreen, %{id: receipt.id})}
  end

  def handle_info({:tap, {:group, group}}, socket) do
    {:noreply, socket |> Mob.Socket.assign(:group, group) |> load_receipts()}
  end

  def handle_info({:tap, :add_manual}, socket) do
    {:noreply, Mob.Socket.push_screen(socket, RisitiApp.Screens.ReceiptFormScreen)}
  end

  def handle_info({:tap, :open_settings}, socket) do
    {:noreply, Mob.Socket.push_screen(socket, RisitiApp.Screens.SettingsScreen)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}
end
