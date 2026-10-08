defmodule RisitiApp.Screens.ApprovalsScreen do
  @moduledoc """
  The approver's side of the phone: what waits for a decision, and
  approved refunds and payment requests waiting to be paid. Tapping one
  opens its details, with Approve and Reject (a rejection needs a note) or
  Mark as paid.

  Everything comes from the team's server and the decisions go straight
  back to it; nothing here is saved on the phone. While it's open, a push
  (which the home screen receives) reloads it: the home screen sends
  `:server_changed` to this screen's registered name.
  """

  use Mob.Screen

  alias RisitiApp.{Accounts, Api, DataDir, Native, Remote}
  alias RisitiApp.Components.{ActionButton, FormField, TransactionItem}

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    # One Approvals screen at a time; the name frees itself when it closes.
    try do
      Process.register(self(), __MODULE__)
    rescue
      ArgumentError -> :already_open
    end

    {:ok,
     socket
     |> Mob.Socket.assign(
       profile: Accounts.current_profile(),
       items: [],
       loading: true,
       selected: nil,
       note: "",
       note_error: nil,
       busy: false
     )
     |> Mob.List.put_renderer(:approvals, &row/1)
     |> load()}
  end

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Column background={:background} fill_height={true}>
      <Header title="Approvals" show_back={true} />
      <Text
        :if={@items == []}
        text={if(@loading, do: "Loading…", else: "Nothing waiting. Expenses, refunds and payment requests from your team appear here.")}
        text_size={14}
        text_color={:muted}
        padding_left={22}
        padding_right={22}
      />
      <List
        :if={@items != []}
        id={:approvals}
        items={@items}
        weight={1}
        padding_left={18}
        padding_right={18}
      />
      {sheet(assigns)}
    </Column>
    """
  end

  defp row(%{transaction: transaction, from: from}) do
    ~MOB"""
    <Column fill_width={true}>
      <Text
        text={"From #{from}"}
        text_size={12}
        text_color={:muted}
        padding_left={4}
        padding_bottom={4}
      />
      {TransactionItem.expand(%{transaction: transaction}, [], %{})}
    </Column>
    """
  end

  defp sheet(%{selected: nil}), do: []

  defp sheet(%{selected: %{transaction: t, from: from}} = assigns) do
    ~MOB"""
    <Sheet
      id={"approval-#{t.id}"}
      detents={[:content]}
      background={:background}
      corner_radius={28}
      on_dismiss={{self(), :close}}
    >
      <Column fill_width={true} padding={20}>
        <Text text={t.vendor} text_size={20} font_weight="bold" text_color={:on_background} />
        <Text text={"From #{from}"} text_size={13} text_color={:muted} />
        <Spacer size={14} />
        {TransactionItem.details(t)}
        {if @selected.has_photo, do: ActionButton.button(nil, "Open the receipt photo", :open_photo, style: :secondary)}
        <Spacer size={16} />
        {actions(assigns)}
      </Column>
    </Sheet>
    """
  end

  # A waiting one gets a note and Reject / Approve; an approved claim gets
  # Mark as paid. Each only for someone the server lets do it.
  defp actions(%{selected: %{transaction: t}, profile: profile} = assigns) do
    cond do
      t.status == "pending" and profile.can_approve ->
        ~MOB"""
        <Column fill_width={true}>
          {FormField.field(
            label: "Note (needed to reject)",
            key: :note,
            value: @note,
            placeholder: "e.g. Please attach the invoice",
            error: @note_error
          )}
          <Row fill_width={true}>
            {ActionButton.button("close", "Reject", :reject, style: :danger, weight: 1)}
            <Spacer size={8} />
            {ActionButton.button("check", "Approve", :approve, weight: 1)}
          </Row>
        </Column>
        """

      t.status == "approved" and t.type != "expense" and profile.can_mark_paid ->
        ActionButton.button("check", "Mark as paid", :pay)

      true ->
        []
    end
  end

  # ── Events ──────────────────────────────────────────────────────────────────

  @impl Mob.Screen
  def handle_info({:loaded, {:ok, %{"transactions" => transactions}}}, socket) do
    {:noreply,
     Mob.Socket.assign(socket,
       loading: false,
       items: Enum.map(transactions, &Remote.transaction/1)
     )}
  end

  def handle_info({:loaded, {:error, error}}, socket) do
    {:noreply,
     socket |> Mob.Socket.assign(:loading, false) |> Native.toast(Api.error_message(error))}
  end

  # A push arrived: something changed on the server.
  def handle_info(:server_changed, socket), do: {:noreply, load(socket)}

  def handle_info({:select, :approvals, index}, socket) do
    {:noreply,
     Mob.Socket.assign(socket,
       selected: Enum.at(socket.assigns.items, index),
       note: "",
       note_error: nil
     )}
  end

  def handle_info({event, :close}, socket) when event in [:tap, :dismiss],
    do: {:noreply, Mob.Socket.assign(socket, selected: nil, note: "", note_error: nil)}

  def handle_info({:change, :note, value}, socket),
    do: {:noreply, Mob.Socket.assign(socket, note: value, note_error: nil)}

  def handle_info({:tap, _}, %{assigns: %{busy: true}} = socket), do: {:noreply, socket}

  def handle_info({:tap, :reject}, socket) do
    if String.trim(socket.assigns.note) == "",
      do: {:noreply, Mob.Socket.assign(socket, :note_error, "Say why, so they know what to fix")},
      else: decide(socket, "reject", "Rejected")
  end

  def handle_info({:tap, :approve}, socket), do: decide(socket, "approve", "Approved")
  def handle_info({:tap, :pay}, socket), do: decide(socket, "pay", "Marked as paid")

  def handle_info({{:decided, message}, {:ok, _}}, socket) do
    {:noreply,
     socket
     |> Native.toast(message)
     |> Mob.Socket.assign(selected: nil, note: "", busy: false)
     |> load()}
  end

  def handle_info({{:decided, _message}, {:error, error}}, socket) do
    {:noreply,
     socket
     |> Mob.Socket.assign(:busy, false)
     |> Native.toast(Api.error_message(error))
     |> load()}
  end

  def handle_info({:tap, :open_photo}, %{assigns: %{selected: %{transaction: t}}} = socket),
    do: {:noreply, download(socket, "/api/transactions/#{t.id}/photo", "receipt-#{t.id}.jpg")}

  def handle_info(
        {:tap, {:open_attachment, id}},
        %{assigns: %{selected: %{transaction: t}}} = socket
      ) do
    case Enum.find(t.attachments, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      attachment ->
        {:noreply, download(socket, "/api/attachments/#{id}", "#{id}-#{attachment.name}")}
    end
  end

  def handle_info({:downloaded, {:ok, path}}, socket),
    do: {:noreply, Native.open_file(socket, path)}

  def handle_info({:downloaded, {:error, error}}, socket),
    do: {:noreply, Native.toast(socket, Api.error_message(error))}

  def handle_info({:tap, :back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp load(socket) do
    profile = socket.assigns.profile
    Native.background(socket, :loaded, fn -> Api.approvals(profile) end)
  end

  # The decision goes to the server; the list reloads when it answers.
  defp decide(socket, decision, done_message) do
    %{selected: %{transaction: t}, note: note, profile: profile} = socket.assigns
    note = if String.trim(note) == "", do: nil, else: String.trim(note)

    {:noreply,
     socket
     |> Mob.Socket.assign(:busy, true)
     |> Native.background({:decided, done_message}, fn ->
       Api.decide(profile, t.id, decision, note)
     end)}
  end

  # Into the app's downloads folder, then the phone's own viewer.
  defp download(socket, path, name) do
    profile = socket.assigns.profile
    dir = DataDir.path("downloads")
    File.mkdir_p!(dir)
    dest = Path.join(dir, String.replace(name, ~r/[^A-Za-z0-9._-]/, "_"))

    socket
    |> Native.toast("Opening…")
    |> Native.background(:downloaded, fn ->
      with :ok <- Api.download(profile, path, dest), do: {:ok, dest}
    end)
  end
end
