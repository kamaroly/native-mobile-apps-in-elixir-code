defmodule RisitiApp.Screens.ReceiptsScreen do
  use Mob.Screen

  alias RisitiApp.Theme

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    {:ok,
     Mob.Socket.assign(socket,
       month_total: "Ksh 12,450",
       by_group: [
         {:food, "Food", "Ksh 6,200"},
         {:fuel, "Fuel", "Ksh 4,500"},
         {:other, "Other", "Ksh 1,750"}
       ]
     )}
  end

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Column background={:background} fill_width={true} fill_height={true}>
      <Row padding_left={22} padding_right={22} padding_top={12} padding_bottom={14}>
        <Column weight={1}>
          <Text text="Monday, 05 Oct" text_size={13} text_color={:muted} />
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
      <Scroll weight={1}>
        <Column padding_left={18} padding_right={18} gap={14}>
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
                text={@month_total}
                text_size={36}
                font_weight="bold"
                letter_spacing={-1.8}
                text_color={Theme.color(:spend_text)}
              />
              <Spacer size={14} />
              <Row gap={8}>
                {Enum.map(@by_group, fn {group, label, amount} -> split_cell(group, label, amount) end)}
              </Row>
            </Column>
          </Box>
          <Spacer size={4} />
          <Button
            text="Naivas Supermarket"
            fill_width={true}
            padding={:space_sm}
            on_tap={{self(), {:open_receipt, 1}}}
          />
          <Button
            text="TotalEnergies Westlands"
            fill_width={true}
            padding={:space_sm}
            on_tap={{self(), {:open_receipt, 2}}}
          />
          <Button
            text="Java House"
            fill_width={true}
            padding={:space_sm}
            on_tap={{self(), {:open_receipt, 3}}}
          />
        </Column>
      </Scroll>
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

  # One of the three boxes under the total: a coloured dot and a label over
  # an amount.
  defp split_cell(group, label, amount) do
    ~MOB"""
    <Box weight={1} background={Theme.color(:spend_chip)} corner_radius={14} padding={10}>
      <Column>
        <Row align={:center}>
          <Box width={7} height={7} corner_radius={4} background={Theme.color(group)} />
          <Spacer size={5} />
          <Text text={label} text_size={11} text_color={Theme.color(:spend_muted)} />
        </Row>
        <Spacer size={3} />
        <Text
          text={amount}
          text_size={13}
          font_weight="semibold"
          text_color={Theme.color(:spend_text)}
        />
      </Column>
    </Box>
    """
  end

  @impl Mob.Screen
  def handle_info({:tap, {:open_receipt, id}}, socket) do
    {:noreply, Mob.Socket.push_screen(socket, RisitiApp.Screens.ReceiptFormScreen, %{id: id})}
  end

  def handle_info({:tap, :add_manual}, socket) do
    {:noreply, Mob.Socket.push_screen(socket, RisitiApp.Screens.ReceiptFormScreen)}
  end

  def handle_info({:tap, :open_settings}, socket) do
    {:noreply, Mob.Socket.push_screen(socket, RisitiApp.Screens.SettingsScreen)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}
end
