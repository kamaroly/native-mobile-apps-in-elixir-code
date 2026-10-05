defmodule RisitiApp.Screens.ReceiptsScreen do
  use Mob.Screen

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Mob.Screen
  def render(_assigns) do
    # Who handles each tap: this screen's process, with a tag naming the action.
    add_tap = {self(), :add_manual}
    settings_tap = {self(), :open_settings}

    ~MOB"""
    <Column background={:background} padding={:space_lg}>
      <Text text="Receipts" text_size={:xl} text_color={:on_background} padding={:space_sm} />
      <Spacer size={8} />
      <Button text="Naivas Supermarket" fill_width={true} padding={:space_sm} on_tap={{self(), {:open_receipt, 1}}} />
      <Spacer size={8} />
      <Button text="TotalEnergies Westlands" fill_width={true} padding={:space_sm} on_tap={{self(), {:open_receipt, 2}}} />
      <Spacer size={8} />
      <Button text="Java House" fill_width={true} padding={:space_sm} on_tap={{self(), {:open_receipt, 3}}} />
      <Spacer size={24} />
      <Button
        text="Add a receipt"
        background={:primary}
        text_color={:on_primary}
        text_size={:lg}
        padding={:space_sm}
        fill_width={true}
        on_tap={add_tap}
      />
      <Spacer size={16} />
      <Button
        text="Settings"
        background={:primary}
        text_color={:on_primary}
        text_size={:lg}
        padding={:space_sm}
        fill_width={true}
        on_tap={settings_tap}
      />
    </Column>
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
