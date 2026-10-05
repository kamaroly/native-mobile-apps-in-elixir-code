defmodule RisitiApp.Screens.ReceiptsScreen do
  use Mob.Screen

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    {:ok,
     Mob.Socket.assign(socket,
       month_total: "Ksh 12,450",
       by_group: [{"Food", "Ksh 6,200"}, {"Fuel", "Ksh 4,500"}, {"Other", "Ksh 1,750"}]
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
          <Box background={:surface_raised} corner_radius={24} padding={20} fill_width={true}>
            <Column>
              <Text text="Spent this month" text_size={13} text_color={:muted} />
              <Spacer size={10} />
              <Text text={@month_total} text_size={36} font_weight="bold" text_color={:on_surface} />
              <Spacer size={14} />
              <Row gap={8}>
                {Enum.map(@by_group, fn {label, amount} -> split_cell(label, amount) end)}
              </Row>
            </Column>
          </Box>

          <Button text="Naivas Supermarket" fill_width={true} padding={:space_sm} on_tap={{self(), {:open_receipt, 1}}} />
          <Button text="TotalEnergies Westlands" fill_width={true} padding={:space_sm} on_tap={{self(), {:open_receipt, 2}}} />
          <Button text="Java House" fill_width={true} padding={:space_sm} on_tap={{self(), {:open_receipt, 3}}} />
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

  # One of the three boxes under the total: a label over an amount.
  defp split_cell(label, amount) do
    ~MOB"""
    <Box weight={1} background={:surface} corner_radius={14} padding={10}>
      <Column>
        <Text text={label} text_size={11} text_color={:muted} />
        <Text text={amount} text_size={13} font_weight="semibold" text_color={:on_surface} />
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
