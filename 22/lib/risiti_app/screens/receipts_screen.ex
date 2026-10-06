defmodule RisitiApp.Screens.ReceiptsScreen do
  @moduledoc """
  Home screen: the chosen month's spend, the transactions, and the ways to
  add one.

  The list can be narrowed three ways at once: by a search, by spending
  group, and by dates (a preset or dates picked on `DateRangeScreen`). The
  spend card shows one month, picked from the last twelve. Tapping a
  transaction opens its details in a sheet.

  KRA receipts saved before KRA could be reached are checked with KRA here,
  one at a time and in the background, each at most once per visit.
  """

  use Mob.Screen

  alias RisitiApp.{Native, Theme, Transactions}
  alias RisitiApp.Components.{ActionButton, TransactionItem}
  alias RisitiApp.Screens.{DateRangeScreen, ReceiptFormScreen, RequestFormScreen, SettingsScreen}
  alias RisitiApp.Transactions.Attachments

  # The month picker offers this many months back from today.
  @months 12

  # Action sheets answer with an atom, so each choice gets one, and these
  # maps turn the atom back into what was chosen.
  @month_actions Map.new(0..(@months - 1), &{:"month_#{&1}", &1})
  @period_actions Map.new(Transactions.periods(), &{:"period_#{&1}", &1})

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    socket =
      socket
      |> Mob.Socket.assign(
        query: "",
        searching: false,
        group: :all,
        period: :all_dates,
        month: Date.beginning_of_month(Transactions.today()),
        selected: nil,
        # KRA checks in flight, id => :tap (the person asked, so say how it
        # went) or :background (quiet), and the ids tried on this visit.
        verifying: %{},
        tried: MapSet.new(),
        locked: RisitiApp.AppLock.enabled?()
      )
      |> Mob.List.put_renderer(:receipts, &list_item/1)
      |> load_receipts()
      |> verify_next()

    socket =
      if socket.assigns.locked,
        do: Native.authenticate(socket, "Unlock your receipts"),
        else: socket

    {:ok, socket}
  end

  defp load_receipts(socket) do
    %{query: query, group: group, period: period, month: month} = socket.assigns

    Mob.Socket.assign(socket,
      items: Transactions.list_transactions(query, group, period),
      summary: Transactions.summary(month)
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
        actions={[search_action(@searching), {"settings", "Settings", :open_settings}]}
      />
      <Column padding_left={18} padding_right={18} padding_bottom={14}>
        <SearchField :if={@searching} query={@query} on_change={{self(), :search}} />
        {if not @searching, do: spend_card(@summary, @month)}
      </Column>
      {chips(@group, @summary.count)}
      <Spacer size={10} />
      {date_pill(@period)}
      <Row fill_width={true} padding_left={22} padding_right={22} padding_top={12} padding_bottom={8}>
        <Text
          text="Transactions"
          text_size={13}
          font_weight="semibold"
          text_color={:muted}
          weight={1}
        />
        <Text
          text={count_label(length(@items))}
          text_size={13}
          font_weight="semibold"
          text_color={:muted}
        />
      </Row>
      <Text
        :if={@items == []}
        text={empty_text(@query, @group, @period)}
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
      {if not @searching, do: dock()}
      <TransactionSheet :if={@selected} transaction={@selected} />
    </Column>
    """
  end

  defp search_action(false), do: {"search", "Search transactions", :toggle_search}
  defp search_action(true), do: {"close", "Close search", :toggle_search}

  defp dock do
    ~MOB"""
    <Row padding={14} gap={8}>
      {ActionButton.button(nil, "Scan receipt", :take_photo, weight: 1)}
      {ActionButton.button(nil, "QR", :scan_qr, style: :secondary, width: 64)}
      {ActionButton.button("add", "Add", :add_menu, style: :secondary, width: 96)}
    </Row>
    """
  end

  # The dark card: the chosen month's spend, split three ways. The month
  # pill opens the month picker.
  defp spend_card(summary, month) do
    ~MOB"""
    <Box
      background={Theme.color(:spend_card)}
      corner_radius={:radius_lg}
      padding={20}
      fill_width={true}
    >
      <Column>
        <Row fill_width={true} align={:center}>
          <Text
            text={spent_label(month)}
            text_size={13}
            text_color={Theme.color(:spend_muted)}
            weight={1}
          />
          <Row
            background={Theme.color(:spend_chip)}
            corner_radius={:radius_pill}
            padding_left={10}
            padding_right={6}
            padding_top={5}
            padding_bottom={5}
            align={:center}
            on_tap={{self(), :pick_month}}
            accessibility_label={"Month: #{month_label(month)}. Change month"}
          >
            <Text
              text={month_label(month)}
              text_size={13}
              font_weight="medium"
              text_color={Theme.color(:spend_text)}
            />
            <Spacer size={2} />
            <Icon name="expand_more" text_size={16} text_color={Theme.color(:spend_text)} />
          </Row>
        </Row>
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
          text={bare_amount(cents)}
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
      ([{:all, "All · #{count}"}] ++
         Enum.map(Transactions.groups() ++ [:claims], &{&1, Transactions.group_label(&1)}))
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

  # The date filter. Outlined while it shows all dates, filled in ink when
  # it's narrowing the list, so a filtered list never passes for a whole one.
  defp date_pill(period) do
    {background, border, text_color} =
      if period == :all_dates,
        do: {:surface, :border, :on_surface},
        else: {:on_background, :on_background, :background}

    ~MOB"""
    <Row padding_left={18} padding_right={18}>
      <Row
        background={background}
        border_color={border}
        border_width={1}
        corner_radius={:radius_pill}
        padding_left={12}
        padding_right={8}
        padding_top={6}
        padding_bottom={6}
        align={:center}
        on_tap={{self(), :pick_period}}
        accessibility_label={"Dates: #{Transactions.period_label(period)}. Change dates"}
      >
        <Text
          text={Transactions.period_label(period)}
          text_size={13}
          font_weight="medium"
          text_color={text_color}
          max_lines={1}
        />
        <Spacer size={2} />
        <Icon name="expand_more" text_size={16} text_color={text_color} />
      </Row>
    </Row>
    """
  end

  # Each row of the list. Rows are expanded lazily, after composites, so the
  # renderer calls the component's expand/3 itself rather than returning a
  # <TransactionItem> tag.
  defp list_item(transaction), do: TransactionItem.expand(%{transaction: transaction}, [], %{})

  @impl Mob.Screen
  def handle_info({:select, :receipts, index}, socket) do
    {:noreply, Mob.Socket.assign(socket, :selected, Enum.at(socket.assigns.items, index))}
  end

  # ── The details sheet ─────────────────────────────────────────────────────

  def handle_info({event, :close_transaction}, socket) when event in [:tap, :dismiss] do
    {:noreply, Mob.Socket.assign(socket, :selected, nil)}
  end

  # A payment request is edited where it was made; anything else on the
  # receipt form.
  def handle_info({:tap, :edit_transaction}, socket) do
    %{id: id, type: type} = socket.assigns.selected

    {screen, params} =
      if type == "payment_request",
        do: {RequestFormScreen, %{id: id, notify: self()}},
        else: {ReceiptFormScreen, %{id: id}}

    {:noreply,
     socket
     |> Mob.Socket.assign(:selected, nil)
     |> Mob.Socket.push_screen(screen, params)}
  end

  # ── Refunds and payment requests ──────────────────────────────────────────

  def handle_info({:tap, :request_refund}, socket) do
    %{id: id} = socket.assigns.selected

    {:noreply,
     socket
     |> Mob.Socket.assign(:selected, nil)
     |> Mob.Socket.push_screen(RequestFormScreen, %{refund_of: id, notify: self()})}
  end

  def handle_info({:tap, :cancel_refund}, socket) do
    {:noreply,
     Native.alert(socket,
       title: "Take back the refund request?",
       message: "It stays as an expense, and nobody will pay it back.",
       buttons: [
         [label: "Take back", style: :destructive, action: :confirm_cancel_refund],
         [label: "Keep", style: :cancel]
       ]
     )}
  end

  def handle_info(
        {:alert, :confirm_cancel_refund},
        %{assigns: %{selected: %{} = refund}} = socket
      ) do
    case Transactions.cancel_refund(refund) do
      {:ok, expense} ->
        {:noreply,
         socket
         |> Native.toast("Refund request taken back")
         |> Mob.Socket.assign(:selected, expense)
         |> load_receipts()}

      {:error, :not_pending} ->
        {:noreply, Native.toast(socket, "It has been decided on, so it stays")}
    end
  end

  # The request form pops back here, and this screen carries on as it was,
  # so the form tells it to reload.
  def handle_info({:request_saved, _transaction}, socket),
    do: {:noreply, load_receipts(socket)}

  def handle_info(
        {:tap, {:open_attachment, id}},
        %{assigns: %{selected: %{} = selected}} = socket
      ) do
    case Enum.find(selected.attachments, &(&1.id == id)) do
      nil -> {:noreply, socket}
      attachment -> {:noreply, Native.open_file(socket, Attachments.path(attachment.file_name))}
    end
  end

  def handle_info({:tap, :delete_transaction}, socket) do
    {:noreply,
     Native.alert(socket,
       title: "Delete this transaction?",
       message: "It will be removed from this phone. This cannot be undone.",
       buttons: [
         [label: "Delete", style: :destructive, action: :confirm_delete],
         [label: "Cancel", style: :cancel]
       ]
     )}
  end

  def handle_info({:alert, :confirm_delete}, %{assigns: %{selected: nil}} = socket),
    do: {:noreply, socket}

  def handle_info({:alert, :confirm_delete}, socket) do
    {:ok, _} = Transactions.delete_transaction(socket.assigns.selected)

    {:noreply,
     socket
     |> Mob.Socket.assign(:selected, nil)
     |> Native.toast("Deleted")
     |> load_receipts()}
  end

  # ── KRA QR codes ───────────────────────────────────────────────────────────

  # The scanner asks for the camera itself if it has to.
  def handle_info({:tap, :scan_qr}, socket), do: {:noreply, Native.scan_qr(socket)}

  # A code that's already saved opens that receipt instead of a duplicate.
  def handle_info({:scan, :result, %{value: value}}, socket) when is_binary(value) do
    case Transactions.find_by_qr(value) do
      nil ->
        {:noreply, Mob.Socket.push_screen(socket, ReceiptFormScreen, %{qr: value})}

      existing ->
        {:noreply,
         socket
         |> Native.toast("You already saved this receipt")
         |> Mob.Socket.assign(:selected, existing)}
    end
  end

  def handle_info({:scan, :permission_denied}, socket) do
    {:noreply, Native.toast(socket, "Camera access is off. Allow it in Settings to scan.")}
  end

  def handle_info({:scan, :not_available}, socket) do
    {:noreply, Native.toast(socket, "The scanner couldn't open. Add the receipt by hand.")}
  end

  # ── Checking receipts with KRA ────────────────────────────────────────────

  def handle_info({:tap, :verify_receipt}, %{assigns: %{selected: %{} = receipt}} = socket) do
    if Transactions.verifiable?(receipt),
      do: {:noreply, socket |> Native.toast("Checking with KRA…") |> start_verify(receipt, :tap)},
      else: {:noreply, socket}
  end

  # Each answer carries the receipt's id, so it lands on the right receipt
  # even if the sheet was closed in the meantime.
  def handle_info({:kra, :result, details, {:verify, id}}, socket) do
    {mode, socket} = finish_verify(socket, id)

    socket =
      case Transactions.get_transaction(id) do
        nil ->
          socket

        receipt ->
          {:ok, verified} = Transactions.mark_verified(receipt)

          socket =
            case socket.assigns.selected do
              %{id: ^id} -> Mob.Socket.assign(socket, :selected, verified)
              _ -> socket
            end

          if mode == :tap,
            do: Native.toast(socket, verified_message(verified, details)),
            else: socket
      end

    {:noreply, socket |> load_receipts() |> verify_next()}
  end

  def handle_info({:kra, :error, reason, {:verify, id}}, socket) do
    {mode, socket} = finish_verify(socket, id)

    socket =
      if mode == :tap,
        do: Native.toast(socket, kra_error_message(reason)),
        else: socket

    {:noreply, verify_next(socket)}
  end

  def handle_info({:tap, :open_on_kra}, %{assigns: %{selected: %{verify_url: url}}} = socket)
      when is_binary(url),
      do: {:noreply, Native.open_url(socket, url)}

  # ── Search ────────────────────────────────────────────────────────────────

  def handle_info({:tap, :toggle_search}, %{assigns: %{searching: true}} = socket) do
    {:noreply, socket |> Mob.Socket.assign(searching: false, query: "") |> load_receipts()}
  end

  def handle_info({:tap, :toggle_search}, socket) do
    {:noreply, Mob.Socket.assign(socket, :searching, true)}
  end

  def handle_info({:change, :search, query}, socket) do
    {:noreply, socket |> Mob.Socket.assign(:query, query) |> load_receipts()}
  end

  # ── The month ─────────────────────────────────────────────────────────────

  def handle_info({:tap, :pick_month}, socket) do
    buttons =
      Transactions.recent_months(@months)
      |> Enum.with_index()
      |> Enum.map(fn {month, i} -> [label: month_label(month, :long), action: :"month_#{i}"] end)

    {:noreply,
     Native.action_sheet(socket,
       title: "Show spending for",
       buttons: buttons ++ [[label: "Cancel", style: :cancel]]
     )}
  end

  def handle_info({:alert, action}, socket) when is_map_key(@month_actions, action) do
    month = Enum.at(Transactions.recent_months(@months), @month_actions[action])
    {:noreply, socket |> Mob.Socket.assign(:month, month) |> load_receipts()}
  end

  # ── Dates ─────────────────────────────────────────────────────────────────

  def handle_info({:tap, :pick_period}, socket) do
    presets =
      Enum.map(Transactions.periods(), fn period ->
        [label: Transactions.period_label(period), action: :"period_#{period}"]
      end)

    {:noreply,
     Native.action_sheet(socket,
       title: "Show transactions for",
       buttons:
         presets ++
           [[label: "Choose dates…", action: :choose_dates], [label: "Cancel", style: :cancel]]
     )}
  end

  def handle_info({:alert, action}, socket) when is_map_key(@period_actions, action) do
    {:noreply, socket |> Mob.Socket.assign(:period, @period_actions[action]) |> load_receipts()}
  end

  # Starts from the dates showing now, so a preset can be adjusted.
  def handle_info({:alert, :choose_dates}, socket) do
    {from, to} = Transactions.date_range(socket.assigns.period)

    {:noreply,
     Mob.Socket.push_screen(socket, DateRangeScreen, %{from: from, to: to, notify: self()})}
  end

  def handle_info({:dates_chosen, from, to}, socket) do
    period = if from == nil and to == nil, do: :all_dates, else: {:dates, from, to}
    {:noreply, socket |> Mob.Socket.assign(:period, period) |> load_receipts()}
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
     Native.alert(socket,
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
    {:noreply, Mob.Socket.push_screen(socket, ReceiptFormScreen, %{photo: path})}
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

  def handle_info({:tap, :add_menu}, socket) do
    {:noreply,
     Native.action_sheet(socket,
       title: "Add",
       buttons: [
         [label: "Add an expense by hand", action: :add_manual],
         [label: "Request a payment", action: :new_payment],
         [label: "Cancel", style: :cancel]
       ]
     )}
  end

  def handle_info({event, :add_manual}, socket) when event in [:tap, :alert] do
    {:noreply, Mob.Socket.push_screen(socket, ReceiptFormScreen)}
  end

  def handle_info({:alert, :new_payment}, socket) do
    {:noreply, Mob.Socket.push_screen(socket, RequestFormScreen, %{notify: self()})}
  end

  def handle_info({:tap, :open_settings}, socket) do
    {:noreply, Mob.Socket.push_screen(socket, SettingsScreen)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # Starts a KRA check for `receipt`. One already running for it is promoted
  # to :tap so the person hears the answer, rather than started twice.
  defp start_verify(socket, receipt, mode) do
    %{verifying: verifying, tried: tried} = socket.assigns

    socket =
      Mob.Socket.assign(socket,
        verifying: Map.put(verifying, receipt.id, mode),
        tried: MapSet.put(tried, receipt.id)
      )

    if Map.has_key?(verifying, receipt.id),
      do: socket,
      else: Native.lookup_kra(socket, receipt.verify_url, {:verify, receipt.id})
  end

  defp finish_verify(socket, id) do
    {mode, verifying} = Map.pop(socket.assigns.verifying, id)
    {mode, Mob.Socket.assign(socket, :verifying, verifying)}
  end

  # Quietly checks saved KRA receipts, one at a time: ones saved while
  # offline, or before KRA answered. `tried` stops a receipt KRA couldn't
  # answer for from being retried over and over on this visit.
  defp verify_next(%{assigns: %{verifying: verifying}} = socket) when map_size(verifying) > 0,
    do: socket

  defp verify_next(socket) do
    case Transactions.next_unverified(socket.assigns.tried) do
      nil -> socket
      receipt -> start_verify(socket, receipt, :background)
    end
  end

  # KRA vouches for the receipt; say so if its total differs from ours.
  defp verified_message(receipt, %{amount_cents: cents})
       when is_integer(cents) and cents != receipt.amount_cents,
       do: "Verified with KRA, but KRA's total is #{Transactions.format_amount(cents)}"

  defp verified_message(_receipt, _details), do: "Verified with KRA"

  # KRA answering "no such receipt" isn't a connection problem.
  defp kra_error_message(:unrecognised),
    do: "KRA has no record of this receipt yet. Try again in a day or two."

  defp kra_error_message(_reason), do: "Couldn't reach KRA. Check your connection and try again."

  defp spent_label(month) do
    if month == Date.beginning_of_month(Transactions.today()),
      do: "Spent this month",
      else: "Spent in #{month_label(month, :long)}"
  end

  # "September" this year, "Sep 2025" before it; `:long` always has the year.
  defp month_label(month, style \\ :short) do
    cond do
      style == :long -> Calendar.strftime(month, "%B %Y")
      month.year == Transactions.today().year -> Calendar.strftime(month, "%B")
      true -> Calendar.strftime(month, "%b %Y")
    end
  end

  # "5,280.50" without the currency: the cells are narrow, and the label
  # above them already says what they are.
  defp bare_amount(cents),
    do: cents |> Transactions.format_short() |> String.replace_prefix("Ksh ", "")

  defp count_label(1), do: "1 item"
  defp count_label(count), do: "#{count} items"

  # Says why the list is empty: a search, a period, a group, or a new book.
  defp empty_text("", :all, :all_dates), do: "No receipts yet. Scan one, or add it by hand."

  defp empty_text("", :all, period),
    do: "Nothing for #{String.downcase(Transactions.period_label(period))}."

  defp empty_text("", :claims, _period),
    do: "No refunds or payment requests yet. Tap Add to request a payment."

  defp empty_text("", group, _period),
    do: "No #{String.downcase(Transactions.group_label(group))} expenses here."

  defp empty_text(_query, _group, _period), do: "Nothing matches your search."
end
