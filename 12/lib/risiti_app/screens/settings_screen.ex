defmodule RisitiApp.Screens.SettingsScreen do
  use Mob.Screen

  alias RisitiApp.Appearance

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    {:ok, Mob.Socket.assign(socket, :appearance, Appearance.current())}
  end

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Scroll background={:background}>
      <Column>
        <Header title="Settings" show_back={true} />
        <Column padding_left={22} padding_right={22} gap={12}>
          <Text text="Appearance" text_size={13} font_weight="medium" text_color={:muted} />
          <Row gap={8}>
            {Enum.map(Appearance.modes(), &appearance_button(&1, @appearance))}
          </Row>
        </Column>
      </Column>
    </Scroll>
    """
  end

  # A segmented control: one pill per mode, the chosen one filled.
  defp appearance_button(mode, current) do
    {background, text_color} =
      if mode == current, do: {:primary, :on_primary}, else: {:surface, :on_surface}

    ~MOB"""
    <Box
      weight={1}
      height={40}
      background={background}
      border_color={if(mode == current, do: :primary, else: :border)}
      border_width={1}
      corner_radius={:radius_pill}
      align={:center}
      on_tap={{self(), {:appearance, mode}}}
      accessibility_label={"Appearance: #{Appearance.label(mode)}"}
    >
      <Text
        text={Appearance.label(mode)}
        text_size={14}
        font_weight="medium"
        text_color={text_color}
      />
    </Box>
    """
  end

  @impl Mob.Screen
  def handle_info({:tap, {:appearance, mode}}, socket) do
    :ok = Appearance.choose(mode)
    {:noreply, Mob.Socket.assign(socket, :appearance, mode)}
  end

  def handle_info({:tap, :back}, socket) do
    {:noreply, Mob.Socket.pop_screen(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}
end
