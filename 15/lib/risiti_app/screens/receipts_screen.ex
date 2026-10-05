defmodule RisitiApp.Screens.ReceiptsScreen do
  use Mob.Screen

  alias RisitiApp.{Native, Theme, Transactions}
  alias RisitiApp.Components.{ActionButton, TransactionItem}

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    socket =
      socket
      |> Mob.Socket.assign(:group, :all)
      |> Mob.Socket.assign(:locked, RisitiApp.AppLock.enabled?())
      |> Mob.List.put_renderer(:receipts, &list_item/1)
      |> load_receipts()

    socket =
      if socket.assigns.locked,
        do: Native.authenticate(socket, "Unlock your receipts"),
        else: socket

    {:ok, socket}
  end

  defp load_receipts(socket) do
    Mob.Socket.assign(socket,
      items: Transactions.list_transactions(socket.assigns.group),
      summary: Transactions.summary()
    )
  end

  @impl Mob.Screen
  def render(%{locked: true}) do
    ~MOB"""
    <Column padding={24} background={:background} fill_height={true}>
      <Spacer size={48} />
      <Text text="Receipts are locked" text_size={:xl} text_color={:on_background} />
      <Spacer size={16} />
      {ActionButton.button(nil, "Unlock", :unlock)}
    </Column>
    """
  end

  def render(assigns) do
    ~MOB"""
    <Column background={:background} fill_width={true} fill_height={true}>
      <Header
        kicker={Calendar.strftime(Transactions.today(), "%A, %d %b")}
        title="Your expenses"
        actions={[{"settings", "Settings", :open_settings}]}
      />
      <Column padding_left={18} padding_right={18} padding_bottom={14}>
        {spend_card(@summary)}
      </Column>
      {chips(@group, @summary.count)}
      <Spacer size={10} />
      <Text
        :if={@items == []}
        text="No receipts yet. Scan one, or add it by hand."
        text_color={:muted}
        text_size={14}
        padding_left={22}
        padding_right={22}
        padding_top={12}
      />
      <List
        :if={@items != []}
        id={:receipts}
        items={@items}
        weight={1}
        padding_left={18}
        padding_right={18}
      />
      <Spacer :if={@items == []} weight={1} />
      <Row padding={14} gap={8}>
        {ActionButton.button(nil, "Scan receipt", :take_photo, weight: 1)}
        {ActionButton.button("add", "Add", :add_manual, style: :secondary, width: 96)}
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

  # Each row of the list. Rows are expanded lazily, after composites, so the
  # renderer calls the component's expand/3 itself rather than returning a
  # <TransactionItem> tag.
  defp list_item(transaction), do: TransactionItem.expand(%{transaction: transaction}, [], %{})

  @impl Mob.Screen
  def handle_info({:select, :receipts, index}, socket) do
    receipt = Enum.at(socket.assigns.items, index)

    {:noreply,
     Mob.Socket.push_screen(socket, RisitiApp.Screens.ReceiptFormScreen, %{id: receipt.id})}
  end

  # ── Scanning ──────────────────────────────────────────────────────────────

  # Asking is cheap when permission is already granted, and it covers the
  # case where the user revoked it in system settings since last time.
  def handle_info({:tap, :take_photo}, socket) do
    {:noreply, Native.request_camera(socket)}
  end

  def handle_info({:permission, :camera, :granted}, socket) do
    {:noreply, Native.take_photo(socket)}
  end

  def handle_info({:permission, :camera, _denied}, socket) do
    {:noreply,
     Mob.Alert.alert(socket,
       title: "Camera access needed",
       message: "Allow camera access in Settings to photograph receipts.",
       buttons: [
         [label: "Open Settings", action: :open_app_settings],
         [label: "Cancel", style: :cancel]
       ]
     )}
  end

  # The form keeps the photo; the camera's file is only temporary.
  def handle_info({:camera, :photo, %{path: path}}, socket) do
    {:noreply,
     Mob.Socket.push_screen(socket, RisitiApp.Screens.ReceiptFormScreen, %{photo: path})}
  end

  def handle_info({:camera, :cancelled}, socket), do: {:noreply, socket}

  def handle_info({:alert, :open_app_settings}, socket) do
    Mob.Device.open_settings(:app)
    {:noreply, socket}
  end

  # ── App lock ──────────────────────────────────────────────────────────────

  def handle_info({:tap, :unlock}, socket) do
    {:noreply, Native.authenticate(socket, "Unlock your receipts")}
  end

  def handle_info({:biometric, :success}, socket) do
    {:noreply, Mob.Socket.assign(socket, :locked, false)}
  end

  # A phone with no fingerprint or face enrolled cannot lock the app; don't
  # lock the user out of their own receipts because of it.
  def handle_info({:biometric, :not_available}, socket) do
    socket = Native.toast(socket, "Biometric unlock is not set up on this phone")
    {:noreply, Mob.Socket.assign(socket, :locked, false)}
  end

  def handle_info({:biometric, _failure}, socket), do: {:noreply, socket}

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
