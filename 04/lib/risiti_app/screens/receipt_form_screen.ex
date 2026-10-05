defmodule RisitiApp.Screens.ReceiptFormScreen do
  use Mob.Screen

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Mob.Screen
  def render(_assigns) do
    go_back = {self(), :back}

    ~MOB"""
    <Column background={:background} padding={:space_lg}>
      <Text text="New receipt" text_size={:xl} text_color={:on_background} padding={:space_sm} />
      <Button text="Go Back" on_tap={go_back} text_size={:lg} padding={:space_sm} />
    </Column>
    """
  end

  @impl Mob.Screen
  def handle_info({:tap, :back}, socket) do
    {:noreply, Mob.Socket.pop_screen(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}
end
