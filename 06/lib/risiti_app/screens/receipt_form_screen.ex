defmodule RisitiApp.Screens.ReceiptFormScreen do
  use Mob.Screen

  @impl Mob.Screen
  def mount(params, _session, socket) do
    # Opened with %{id: id} to edit a receipt, or with no params for a new one.
    {:ok, Mob.Socket.assign(socket, :id, params[:id])}
  end

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Column background={:background} padding={:space_lg}>
      <Button text="Go Back" text_size={:lg} padding={:space_sm} on_tap={{self(), :back}} />
      <Spacer size={16} />
      <Text text={title(@id)} text_size={:xl} text_color={:on_background} />
    </Column>
    """
  end

  defp title(nil), do: "New receipt"
  defp title(id), do: "Editing receipt #{id}"

  @impl Mob.Screen
  def handle_info({:tap, :back}, socket) do
    {:noreply, Mob.Socket.pop_screen(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}
end
