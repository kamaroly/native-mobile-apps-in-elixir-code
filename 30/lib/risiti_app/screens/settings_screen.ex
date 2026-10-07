defmodule RisitiApp.Screens.SettingsScreen do
  use Mob.Screen

  alias RisitiApp.{Accounts, Appearance, Native}
  alias RisitiApp.Accounts.Profile
  alias RisitiApp.Components.ActionButton

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    {:ok,
     Mob.Socket.assign(socket,
       appearance: Appearance.current(),
       app_lock: RisitiApp.AppLock.enabled?(),
       profile: Accounts.current_profile()
     )}
  end

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Scroll background={:background}>
      <Column>
        <Header title="Settings" show_back={true} />
        <Column padding_left={22} padding_right={22} gap={12}>
          <Text text="Your team" text_size={13} font_weight="medium" text_color={:muted} />
          {account(@profile)}
          <Spacer size={8} />
          <Text text="Appearance" text_size={13} font_weight="medium" text_color={:muted} />
          <Row gap={8}>
            {Enum.map(Appearance.modes(), &appearance_button(&1, @appearance))}
          </Row>
          <Spacer size={8} />
          <Text text="Security" text_size={13} font_weight="medium" text_color={:muted} />
          {toggle_row("Lock with fingerprint / face", @app_lock, :app_lock)}
        </Column>
      </Column>
    </Scroll>
    """
  end

  # Signed in: who, and which team. Not signed in: the book stays here.
  defp account(profile) do
    if Profile.connected?(profile) do
      kind = if Profile.personal?(profile), do: "Personal book", else: "Business"

      ~MOB"""
      <Column gap={8}>
        <Text text={profile.name || profile.phone} text_size={15} text_color={:on_background} />
        <Text text={"#{profile.team_name} · #{kind}"} text_size={13} text_color={:muted} />
        {ActionButton.button(nil, "Disconnect", :disconnect, style: :secondary)}
      </Column>
      """
    else
      ~MOB"""
      <Column gap={8}>
        <Text
          text="Not signed in. Your receipts are kept on this phone. Sign in to send them to your team."
          text_size={13}
          text_color={:muted}
        />
        {ActionButton.button("user", "Sign in", :sign_in)}
      </Column>
      """
    end
  end

  defp toggle_row(label, value, key) do
    ~MOB"""
    <Row
      fill_width={true}
      align={:center}
      background={:surface}
      border_color={:border}
      border_width={1}
      corner_radius={16}
      padding_left={16}
      padding_right={12}
      padding_top={8}
      padding_bottom={8}
    >
      <Text text={label} text_size={15} text_color={:on_surface} weight={1} />
      <Spacer size={12} />
      <Toggle value={value} on_change={{self(), key}} accessibility_label={label} />
    </Row>
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

  # A toggle sends its new value; the phone may send it as a string.
  def handle_info({:change, :app_lock, value}, socket) do
    enabled = value in [true, "true"]
    :ok = RisitiApp.AppLock.set(enabled)
    {:noreply, Mob.Socket.assign(socket, :app_lock, enabled)}
  end

  def handle_info({:tap, :sign_in}, socket),
    do: {:noreply, Mob.Socket.push_screen(socket, RisitiApp.Screens.PhoneScreen)}

  def handle_info({:tap, :disconnect}, socket) do
    {:noreply,
     Native.alert(socket,
       title: "Disconnect from #{socket.assigns.profile.team_name}?",
       message: "Your receipts stay on this phone. Sign in again to send new ones.",
       buttons: [
         [label: "Disconnect", style: :destructive, action: :confirm_disconnect],
         [label: "Cancel", style: :cancel]
       ]
     )}
  end

  def handle_info({:alert, :confirm_disconnect}, socket) do
    {:ok, profile} = Accounts.disconnect(socket.assigns.profile)
    {:noreply, Mob.Socket.assign(socket, :profile, profile)}
  end

  def handle_info({:tap, :back}, socket) do
    {:noreply, Mob.Socket.pop_screen(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}
end
