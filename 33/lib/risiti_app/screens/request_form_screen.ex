defmodule RisitiApp.Screens.RequestFormScreen do
  @moduledoc """
  Ask for money: a refund of a saved expense, or a payment to be made.

  Mount params:

    * `%{refund_of: id}` — claim that expense back. The amount is its total,
      and the money goes by M-Pesa to a phone number; the expense becomes a
      refund.
    * `%{}` — request a payment: amount, who is paid and what for, its
      category, and how to pay (send money to a phone, a Buy Goods till, or
      a paybill and account), with optional attachments: an invoice or a
      quotation, as photos or PDFs. It can pay a supplier, or be an advance
      to the person themselves.
    * `%{id: id}` — edit a payment request already made.
    * `notify: pid` (any) — the screen that opened the form. It gets
      `{:request_saved, transaction}` after a save, because the screen it
      pops back to carries on as it was rather than mounting again.

  Saved requests wait for approval (see `RisitiApp.Transactions`).
  """

  use Mob.Screen

  alias RisitiApp.{Native, Transactions}
  alias RisitiApp.Components.{ActionButton, FormField}
  alias RisitiApp.Transactions.{Attachment, Attachments, Transaction}

  @fields [:amount, :vendor, :description, :phone, :till_number, :paybill_number, :account_number]

  @methods ~w(send_money till paybill)

  @categories Transaction.categories()
  @category_actions @categories
                    |> Enum.with_index()
                    |> Map.new(fn {category, i} -> {:"category_#{i}", category} end)

  @impl Mob.Screen
  def mount(params, _session, socket) do
    {mode, draft} = draft(params)

    socket =
      socket
      |> Mob.Socket.assign(mode: mode, draft: draft, notify: params[:notify], errors: %{})
      |> Mob.Socket.assign(inputs(mode, draft))
      # New ones, copied in as soon as they're added (see Attachments), and
      # deleted again if the request is never sent.
      |> Mob.Socket.assign(:attachments, [])

    {:ok, socket}
  end

  defp draft(%{refund_of: id}), do: {:refund, Transactions.get_transaction!(id)}
  defp draft(%{id: id}), do: {:edit, Transactions.get_transaction!(id)}
  defp draft(_params), do: {:new, Transactions.new_payment()}

  # A refund starts with room for a note, not the expense's description;
  # everything else starts from the draft.
  defp inputs(:refund, draft), do: Keyword.merge(inputs(draft), description: "")
  defp inputs(_mode, draft), do: inputs(draft)

  defp inputs(draft) do
    [
      method: if(draft.method in @methods, do: draft.method, else: "send_money"),
      pay_to: draft.pay_to || "supplier",
      category: draft.category,
      amount: Transactions.amount_input(draft.amount_cents),
      vendor: draft.vendor || "",
      description: draft.description || "",
      phone: local_phone(draft.phone),
      till_number: draft.till_number || "",
      paybill_number: draft.paybill_number || "",
      account_number: draft.account_number || ""
    ]
  end

  # "+254712345678" back to the way it was typed: "0712345678".
  defp local_phone("+254" <> rest), do: "0" <> rest
  defp local_phone(phone), do: phone || ""

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Column background={:background} fill_width={true} fill_height={true}>
      <Header title={title(@mode)} show_back={true} />
      <Scroll weight={1}>
        <Column padding_left={18} padding_right={18} padding_bottom={16} fill_width={true}>
          {intro(assigns)}
          <Spacer size={16} />
          {pay_with(assigns)}
          <Text :if={@errors[:base]} text={@errors[:base]} text_size={13} text_color={:error} />
        </Column>
      </Scroll>
      <Column fill_width={true} padding_left={18} padding_right={18} padding_bottom={16}>
        <Text
          text="It will be reviewed by your team. You'll see the answer on the home screen."
          text_size={12}
          text_color={:muted}
          padding_bottom={8}
        />
        {ActionButton.button(
          "check",
          if(@mode == :edit, do: "Save", else: "Send request"),
          :submit
        )}
      </Column>
    </Column>
    """
  end

  # A refund shows the expense it's for; a payment asks what, for whom and
  # how much.
  defp intro(%{mode: :refund, draft: expense} = assigns) do
    ~MOB"""
    <Column fill_width={true}>
      <Box
        background={:surface}
        border_color={:border}
        border_width={1}
        corner_radius={16}
        padding={14}
        fill_width={true}
      >
        <Column fill_width={true}>
          <Text text="Refund for" text_size={12} text_color={:muted} />
          <Text
            text={expense.vendor}
            text_size={17}
            font_weight="semibold"
            text_color={:on_surface}
            max_lines={1}
          />
          <Text
            text={Calendar.strftime(expense.date, "%d %b %Y") <> " · " <> expense.category}
            text_size={12}
            text_color={:muted}
            max_lines={1}
          />
          <Spacer size={10} />
          <Text
            text={Transactions.format_amount(expense.amount_cents)}
            text_size={24}
            font_weight="bold"
            text_color={:on_surface}
          />
        </Column>
      </Box>
      <Spacer size={16} />
      {FormField.field(
        label: "Note for your team (optional)",
        key: :description,
        value: @description,
        placeholder: "e.g. Paid for the client lunch with my own money",
        error: @errors[:description]
      )}
    </Column>
    """
  end

  defp intro(assigns) do
    ~MOB"""
    <Column fill_width={true}>
      {FormField.field(
        label: "Amount (Ksh)",
        key: :amount,
        value: @amount,
        placeholder: "e.g. 2,500",
        keyboard: :decimal,
        error: @errors[:amount]
      )}
      {FormField.field(
        label: "Who is being paid?",
        key: :vendor,
        value: @vendor,
        placeholder: "e.g. Kenya Power, or John Otieno",
        error: @errors[:vendor]
      )}
      {FormField.field(
        label: "What is it for?",
        key: :description,
        value: @description,
        placeholder: "e.g. Fuel for the delivery van",
        error: @errors[:description]
      )}
      {category_field(assigns)}
      <Text text="This pays" text_size={13} font_weight="medium" text_color={:on_background} />
      <Spacer size={6} />
      <Row fill_width={true} gap={8}>
        {pill("A supplier", {:pay_to, "supplier"}, @pay_to == "supplier")}
        {pill("Me (an advance)", {:pay_to, "self"}, @pay_to == "self")}
      </Row>
    </Column>
    """
  end

  defp category_field(assigns) do
    ~MOB"""
    <Column fill_width={true} padding_bottom={12}>
      <Text text="Category" text_size={13} font_weight="medium" text_color={:on_background} />
      <Spacer size={6} />
      <Row
        fill_width={true}
        height={52}
        background={:surface}
        border_color={:border}
        border_width={1}
        corner_radius={16}
        padding_left={16}
        padding_right={12}
        align={:center}
        on_tap={{self(), :pick_category}}
        accessibility_label={"Category: #{@category}. Change category"}
      >
        <Text text={@category} text_size={16} text_color={:on_surface} weight={1} />
        <Icon name="expand_more" text_size={20} text_color={:muted} />
      </Row>
    </Column>
    """
  end

  # A refund goes to a phone. A payment picks send money, till or paybill,
  # and can carry attachments.
  defp pay_with(%{mode: :refund} = assigns) do
    ~MOB"""
    <Column fill_width={true}>
      {FormField.field(
        label: "M-Pesa number for the refund",
        key: :phone,
        value: @phone,
        placeholder: "e.g. 0712 345 678",
        keyboard: :phone,
        hint: "The number the money should go to.",
        error: @errors[:phone]
      )}
    </Column>
    """
  end

  defp pay_with(assigns) do
    ~MOB"""
    <Column fill_width={true}>
      <Text text="Pay with" text_size={13} font_weight="medium" text_color={:on_background} />
      <Spacer size={6} />
      <Row fill_width={true} gap={8}>
        {Enum.map(methods(), &pill(method_label(&1), {:method, &1}, &1 == @method))}
      </Row>
      <Spacer size={16} />
      {method_fields(assigns)}
      <Spacer size={4} />
      {attachments_section(@draft.attachments, @attachments)}
    </Column>
    """
  end

  # Inside ~MOB, @methods would be an assign, so the list comes from a function.
  defp methods, do: @methods

  defp method_fields(%{method: "send_money"} = assigns) do
    ~MOB"""
    <Column fill_width={true}>
      {FormField.field(
        label: "Phone number to send to",
        key: :phone,
        value: @phone,
        placeholder: "e.g. 0712 345 678",
        keyboard: :phone,
        error: @errors[:phone]
      )}
    </Column>
    """
  end

  defp method_fields(%{method: "till"} = assigns) do
    ~MOB"""
    <Column fill_width={true}>
      {FormField.field(
        label: "Till number",
        key: :till_number,
        value: @till_number,
        placeholder: "e.g. 832909",
        keyboard: :number,
        error: @errors[:till_number]
      )}
    </Column>
    """
  end

  defp method_fields(assigns) do
    ~MOB"""
    <Column fill_width={true}>
      {FormField.field(
        label: "Paybill (business) number",
        key: :paybill_number,
        value: @paybill_number,
        placeholder: "e.g. 888880",
        keyboard: :number,
        error: @errors[:paybill_number]
      )}
      {FormField.field(
        label: "Account number",
        key: :account_number,
        value: @account_number,
        placeholder: "e.g. 1234567",
        error: @errors[:account_number]
      )}
    </Column>
    """
  end

  # A choice of two or three, as pills that share the row.
  defp pill(label, tag, selected?) do
    {background, text_color, border} =
      if selected?,
        do: {:primary, :on_primary, :primary},
        else: {:surface, :on_surface, :border}

    ~MOB"""
    <Box
      weight={1}
      height={40}
      background={background}
      border_color={border}
      border_width={1}
      corner_radius={:radius_pill}
      align={:center}
      on_tap={{self(), tag}}
      accessibility_label={label}
    >
      <Text text={label} text_size={13} font_weight="medium" text_color={text_color} />
    </Box>
    """
  end

  defp attachments_section(saved, added) do
    full? = length(saved) + length(added) >= Attachments.max_count()

    ~MOB"""
    <Column fill_width={true} padding_bottom={12}>
      <Text
        text="Attachments (optional)"
        text_size={13}
        font_weight="medium"
        text_color={:on_background}
      />
      <Spacer size={2} />
      <Text
        text={"An invoice, quotation or photo. Images or PDFs, up to #{Attachments.max_count()}."}
        text_size={12}
        text_color={:muted}
      />
      <Spacer size={8} />
      {Enum.map(saved, &attachment_row(&1, nil))}
      {Enum.with_index(added, &attachment_row(&1, &2))}
      <Row :if={not full?} fill_width={true} gap={8}>
        {ActionButton.button(nil, "Take photo", :attach_photo, style: :secondary, weight: 1)}
        {ActionButton.button("add", "Add file", :attach_file, style: :secondary, weight: 1)}
      </Row>
    </Column>
    """
  end

  # One already saved with the request (index nil) is shown, but stays; a
  # new one can be removed.
  defp attachment_row(attachment, index) do
    ~MOB"""
    <Column fill_width={true} padding_bottom={8}>
      <Row
        fill_width={true}
        align={:center}
        background={:surface}
        border_color={:border}
        border_width={1}
        corner_radius={14}
        padding={8}
      >
        {attachment_thumb(attachment)}
        <Spacer size={10} />
        <Column weight={1}>
          <Text
            text={attachment.name}
            text_size={14}
            font_weight="medium"
            text_color={:on_surface}
            max_lines={1}
          />
          <Text text={Attachments.format_size(attachment.size)} text_size={12} text_color={:muted} />
        </Column>
        {remove_button(attachment, index)}
      </Row>
    </Column>
    """
  end

  defp remove_button(_attachment, nil), do: []

  defp remove_button(attachment, index) do
    ~MOB"""
    <Box
      width={36}
      height={36}
      corner_radius={10}
      align={:center}
      on_tap={{self(), {:remove_attachment, index}}}
      accessibility_label={"Remove #{attachment.name}"}
    >
      <Icon name="close" text_size={18} text_color={:muted} />
    </Box>
    """
  end

  defp attachment_thumb(attachment) do
    if Attachment.image?(attachment) and File.regular?(Attachments.path(attachment.file_name)) do
      ~MOB"""
      <Image
        src={Attachments.path(attachment.file_name)}
        width={40}
        height={40}
        corner_radius={10}
        content_mode={:fill}
      />
      """
    else
      ~MOB"""
      <Box width={40} height={40} corner_radius={10} background={:surface_raised} align={:center}>
        <Text text="PDF" text_size={11} font_weight="bold" text_color={:muted} />
      </Box>
      """
    end
  end

  # ── Events ──────────────────────────────────────────────────────────────

  @impl Mob.Screen
  def handle_info({:change, key, value}, socket) when key in @fields do
    {:noreply,
     socket
     |> Mob.Socket.assign(key, value)
     |> Mob.Socket.assign(:errors, Map.delete(socket.assigns.errors, key))}
  end

  # Switching method clears the errors of the fields that just went away.
  def handle_info({:tap, {:method, method}}, socket) do
    {:noreply, Mob.Socket.assign(socket, method: method, errors: %{})}
  end

  def handle_info({:tap, {:pay_to, pay_to}}, socket) do
    {:noreply, Mob.Socket.assign(socket, :pay_to, pay_to)}
  end

  def handle_info({:tap, :pick_category}, socket) do
    buttons =
      @categories
      |> Enum.with_index()
      |> Enum.map(fn {category, i} -> [label: category, action: :"category_#{i}"] end)

    {:noreply,
     Native.action_sheet(socket,
       title: "Category",
       buttons: buttons ++ [[label: "Cancel", style: :cancel]]
     )}
  end

  def handle_info({:alert, action}, socket) when is_map_key(@category_actions, action) do
    {:noreply, Mob.Socket.assign(socket, :category, @category_actions[action])}
  end

  # ── Attachments ─────────────────────────────────────────────────────────

  def handle_info({:tap, :attach_photo}, socket), do: {:noreply, Native.request_camera(socket)}

  def handle_info({:permission, :camera, :granted}, socket),
    do: {:noreply, Native.take_photo(socket)}

  def handle_info({:permission, :camera, _denied}, socket) do
    {:noreply,
     Native.toast(socket, "Camera access is off. Allow it in Settings, or add a file instead.")}
  end

  def handle_info({:camera, :photo, %{path: path}}, socket) do
    name = "Photo #{length(socket.assigns.attachments) + 1}.jpg"
    {:noreply, add_attachments(socket, [{path, name, "image/jpeg"}])}
  end

  def handle_info({:tap, :attach_file}, socket), do: {:noreply, Native.pick_files(socket)}

  def handle_info({:files, :picked, items}, socket) do
    files =
      Enum.map(items, fn item ->
        name = item[:name] || "File"
        {item[:path], name, picked_type(item[:mime], name)}
      end)

    {:noreply, add_attachments(socket, files)}
  end

  def handle_info({:tap, {:remove_attachment, index}}, socket) do
    {removed, rest} = List.pop_at(socket.assigns.attachments, index)
    if removed, do: Attachments.delete([removed])
    {:noreply, Mob.Socket.assign(socket, :attachments, rest)}
  end

  # ── Sending ─────────────────────────────────────────────────────────────

  def handle_info({:tap, :submit}, socket) do
    with {:ok, attrs} <- build_attrs(socket.assigns),
         {:ok, saved} <- save(socket.assigns, attrs) do
      if pid = socket.assigns.notify, do: send(pid, {:request_saved, saved})

      {:noreply,
       socket
       |> Native.toast(saved_message(socket.assigns.mode))
       |> Mob.Socket.pop_screen()}
    else
      {:error, :paid} ->
        {:noreply, Native.toast(socket, "It has been paid, so it can't change")}

      {:error, :not_expense} ->
        {:noreply, Native.toast(socket, "A refund was already requested for it")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, Mob.Socket.assign(socket, :errors, changeset_errors(changeset))}

      {:error, errors} ->
        {:noreply, Mob.Socket.assign(socket, :errors, errors)}
    end
  end

  # Files copied in for a request that's never sent go too.
  def handle_info({:tap, :back}, socket) do
    Attachments.delete(socket.assigns.attachments)
    {:noreply, Mob.Socket.pop_screen(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # Copies each file in, up to the limit, and says what couldn't be added.
  defp add_attachments(socket, files) do
    %{draft: draft, attachments: added} = socket.assigns
    room = Attachments.max_count() - length(draft.attachments) - length(added)
    {fits, over} = Enum.split(files, max(room, 0))

    {stored, problems} =
      Enum.reduce(fits, {[], []}, fn file, {stored, problems} ->
        case store(file) do
          {:ok, attachment} -> {[attachment | stored], problems}
          {:error, problem} -> {stored, [problem | problems]}
        end
      end)

    problems =
      Enum.reverse(problems) ++
        if(over == [], do: [], else: ["Only #{Attachments.max_count()} attachments fit"])

    socket = Mob.Socket.assign(socket, :attachments, added ++ Enum.reverse(stored))

    case problems do
      [] -> socket
      _ -> Native.toast(socket, Enum.join(problems, ". "))
    end
  end

  defp store({_path, name, nil}), do: {:error, "#{name} isn't an image or PDF"}

  defp store({path, name, type}) do
    case Attachments.store(path, name, type) do
      {:ok, attachment} -> {:ok, attachment}
      {:error, :too_large} -> {:error, "#{name} is over 10 MB"}
      {:error, :unsupported} -> {:error, "#{name} isn't an image or PDF"}
      {:error, _} -> {:error, "#{name} couldn't be added"}
    end
  end

  # Trust a specific type from the picker; otherwise go by the name.
  defp picked_type(mime, name) when mime in [nil, "", "application/octet-stream"],
    do: Attachments.content_type(name)

  defp picked_type(mime, _name), do: mime

  defp save(%{mode: :new, attachments: files}, attrs),
    do: Transactions.create_transaction(attrs, files)

  # Compared with the row as it's saved, as the receipt form does.
  defp save(%{mode: :edit, draft: draft, attachments: files}, attrs),
    do: Transactions.update_transaction(Transactions.get_transaction!(draft.id), attrs, files)

  defp save(%{mode: :refund, draft: expense}, attrs),
    do: Transactions.request_refund(expense, attrs)

  defp saved_message(:edit), do: "Request saved"
  defp saved_message(_new), do: "Request sent for approval"

  @doc false
  # The form's inputs as changeset attrs. A refund keeps its expense's
  # figures and adds how to pay it back. A payment's amount needs parsing
  # first, and only the chosen method's fields are sent, so switching
  # method clears the others.
  def build_attrs(%{mode: :refund} = assigns) do
    note = String.trim(assigns.description)

    {:ok,
     %{
       method: "send_money",
       phone: assigns.phone,
       description: join_note(assigns.draft.description, note)
     }}
  end

  def build_attrs(assigns) do
    case Transactions.parse_amount(assigns.amount) do
      {:ok, cents} ->
        blank = %{phone: nil, till_number: nil, paybill_number: nil, account_number: nil}

        method_attrs =
          case assigns.method do
            "send_money" -> Map.take(assigns, [:phone])
            "till" -> Map.take(assigns, [:till_number])
            "paybill" -> Map.take(assigns, [:paybill_number, :account_number])
          end

        {:ok,
         blank
         |> Map.merge(method_attrs)
         |> Map.merge(%{
           type: "payment_request",
           pay_to: assigns.pay_to,
           date: assigns.draft.date,
           amount_cents: cents,
           vendor: assigns.vendor,
           description: assigns.description,
           category: assigns.category,
           method: assigns.method,
           source: "manual"
         })}

      :error ->
        {:error, %{amount: "enter an amount like 2500 or 2,500.50"}}
    end
  end

  defp join_note(description, ""), do: description
  defp join_note(description, note) when description in [nil, ""], do: note
  defp join_note(description, note), do: "#{description} — #{note}"

  defp changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Map.new(fn
      {:amount_cents, [message | _]} -> {:amount, "Amount #{message}"}
      {:vendor, [_ | _]} -> {:vendor, "Say who is being paid"}
      {field, [message | _]} -> {field, message_for(field, message)}
    end)
  end

  # "enter the till number" reads fine alone; "is 5 to 7 digits" needs its
  # field in front.
  defp message_for(field, "is " <> _ = message), do: "#{humanize(field)} #{message}"
  defp message_for(_field, message), do: String.capitalize(message)

  defp humanize(field),
    do: field |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp title(:refund), do: "Request refund"
  defp title(:edit), do: "Edit payment request"
  defp title(:new), do: "Request payment"

  defp method_label("send_money"), do: "Send money"
  defp method_label("till"), do: "Till"
  defp method_label("paybill"), do: "Paybill"
end
