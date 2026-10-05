defmodule RisitiApp.Screens.ReceiptsScreen do
  use Mob.Screen

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Mob.Screen
  def render(_assigns) do
    ~MOB"""
    <Column background={:background} padding={:space_lg}>
      <Text text="Receipts" text_size={:xl} text_color={:on_background} padding={:space_sm} />
      <Text text="No receipts yet." text_color={:muted} padding={:space_sm} />
    </Column>
    """
  end
end
