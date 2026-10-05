defmodule RisitiApp.Screens.SettingsScreen do
  use Mob.Screen

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    {:ok, Mob.Socket.assign(socket, :appearance, :light)}
  end

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Scroll background={:background}>
      <Column padding={:space_lg} gap={16}>
        <Button
          text="Go Back"
          background={:surface}
          text_color={:on_surface}
          padding={:space_sm}
          on_tap={{self(), :back}}
        />
        <Text text="Settings" text_size={26} font_weight="bold" text_color={:on_background} />
        <Text text="Appearance" text_size={13} font_weight="medium" text_color={:muted} />
        <Row gap={8}>
          {appearance_button("System", :system, @appearance)}
          {appearance_button("Light", :light, @appearance)}
          {appearance_button("Dark", :dark, @appearance)}
        </Row>
      </Column>
    </Scroll>
    """
  end

  # A segmented control: one pill per mode, the chosen one filled.
  defp appearance_button(label, mode, current) do
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
      accessibility_label={"Appearance: #{label}"}
    >
      <Text text={label} text_size={14} font_weight="medium" text_color={text_color} />
    </Box>
    """
  end

  @impl Mob.Screen
  def handle_info({:tap, {:appearance, mode}}, socket) do
    Mob.Theme.set(theme_for(mode))
    {:noreply, Mob.Socket.assign(socket, :appearance, mode)}
  end

  def handle_info({:tap, :back}, socket) do
    {:noreply, Mob.Socket.pop_screen(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp theme_for(:system), do: RisitiApp.Theme.Adaptive
  defp theme_for(:light), do: RisitiApp.Theme.Light
  defp theme_for(:dark), do: RisitiApp.Theme.Dark
end
