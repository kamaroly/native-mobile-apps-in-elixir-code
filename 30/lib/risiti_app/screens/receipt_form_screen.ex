defmodule RisitiApp.Screens.ReceiptFormScreen do
  @moduledoc """
  Confirm a photographed receipt, add an expense by hand, or edit a saved
  one.

  Mount params:

    * `%{photo: tmp_path}` — a photo was just taken: keep it and read it on
      the phone, then fill in what it found.
    * `%{qr: content}` — a QR code was just scanned. KRA's record of the
      receipt is fetched, and the camera opens for a photo of it (cancel to
      go without).
    * `%{id: id}` — edit a saved transaction.
    * `%{}` — enter an expense by hand.

  A photo can be added, retaken or removed from any of these, and a QR code
  scanned when the photo didn't have a readable one. What's read off a photo
  or fetched from KRA only fills fields the person hasn't typed in, and a
  photo never overwrites what KRA said.
  """

  use Mob.Screen

  alias RisitiApp.{Native, Transactions}
  alias RisitiApp.Receipts.{OcrParser, Photos, QrParser}
  alias RisitiApp.Components.{ActionButton, FormField, Header, KraBadge}
  alias RisitiApp.Transactions.Transaction

  @categories Transaction.categories()
  @category_actions @categories
                    |> Enum.with_index()
                    |> Map.new(fn {category, i} -> {:"category_#{i}", category} end)

  @text_fields [:date, :vendor, :description, :amount]

  @impl Mob.Screen
  def mount(params, _session, socket) do
    receipt =
      case params do
        %{id: id} -> Transactions.get_transaction!(id)
        %{qr: qr} -> Transactions.new_from_qr(qr)
        _ -> %Transaction{date: Transactions.today(), category: "Other"}
      end

    socket =
      Mob.Socket.assign(socket,
        receipt: receipt,
        # The photo the saved receipt already had: a replaced one is deleted
        # on save, and a new, unsaved one on back.
        saved_photo: receipt.photo_path,
        date: Date.to_iso8601(receipt.date),
        vendor: receipt.vendor || "",
        description: receipt.description || "",
        amount: Transactions.amount_input(receipt.amount_cents),
        category: receipt.category,
        # Fields the person has typed in, which a reading must not overwrite.
        touched: MapSet.new(),
        # Fields filled from KRA's record, which a photo must not overwrite.
        from_kra: MapSet.new(),
        reading: false,
        notice: nil,
        viewing_photo: false,
        errors: %{}
      )
      |> duplicate_check()

    socket =
      case params do
        %{photo: tmp} -> read_photo(socket, tmp)
        %{qr: _} -> socket |> lookup_kra() |> Native.request_camera()
        _ -> socket
      end

    {:ok, socket}
  end

  # The receipt photo, full screen, with a button to save it to the gallery.
  @impl Mob.Screen
  def render(%{viewing_photo: true} = assigns) do
    ~MOB"""
    <Column background={:background} fill_height={true}>
      <Row fill_width={true} align={:center} padding={12} gap={12}>
        {Header.icon_button("close", "Close photo", {self(), :close_photo})}
        <Text
          text={if @vendor == "", do: "Receipt photo", else: @vendor}
          text_size={16}
          font_weight="semibold"
          text_color={:on_background}
          max_lines={1}
          weight={1}
        />
        {ActionButton.button(nil, "Save", :save_photo, width: 96)}
      </Row>
      <Image
        src={Photos.path(@receipt.photo_path)}
        content_mode={:fit}
        fill_width={true}
        weight={1}
      />
    </Column>
    """
  end

  def render(assigns) do
    ~MOB"""
    <Column background={:background} fill_height={true}>
      <Header title={if @receipt.id, do: "Edit receipt", else: "New receipt"} show_back={true} />
      <Scroll weight={1}>
        <Column padding_left={22} padding_right={22}>
          {photo_section(assigns)}
          <Spacer size={12} />
          <Box
            :if={@notice}
            background={:surface}
            border_color={:border}
            border_width={1}
            corner_radius={16}
            padding={12}
            fill_width={true}
          >
            <Text text={@notice} text_size={13} text_color={:on_surface} />
          </Box>
          <Spacer :if={@notice} size={12} />
          {qr_section(assigns)}
          <Spacer size={16} />
          {FormField.field(
            label: "Date on receipt",
            key: :date,
            value: @date,
            placeholder: "YYYY-MM-DD, e.g. 2026-09-23",
            hint: "Year-month-day, as printed on the receipt.",
            error: @errors[:date]
          )}
          {FormField.field(
            label: "Vendor (shop or business name)",
            key: :vendor,
            value: @vendor,
            placeholder: "e.g. Naivas Westlands",
            error: @errors[:vendor]
          )}
          {FormField.field(
            label: "Description (optional)",
            key: :description,
            value: @description,
            placeholder: "e.g. Office stationery",
            hint: "What you bought, so you can find it later.",
            error: @errors[:description]
          )}
          {FormField.field(
            label: "Amount paid (Ksh)",
            key: :amount,
            value: @amount,
            placeholder: "e.g. 1,250.50",
            keyboard: :decimal,
            hint: "The total on the receipt, including VAT.",
            error: @errors[:amount]
          )}
          <Text text="Category" text_size={13} font_weight="medium" text_color={:on_background} />
          <Spacer size={6} />
          <Row
            fill_width={true}
            height={52}
            background={:surface}
            border_color={if(@errors[:category], do: :error, else: :border)}
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
          <Text
            :if={@errors[:category]}
            text={@errors[:category]}
            text_size={12}
            text_color={:error}
          />
          <Spacer size={16} />
          <Text :if={@errors[:base]} text={@errors[:base]} text_color={:error} />
        </Column>
      </Scroll>
      <Row padding={14} gap={8}>
        {if @receipt.id,
          do: ActionButton.button("trash", "Delete", :delete, style: :danger, width: 120)}
        {ActionButton.button(
          "check",
          if(@reading, do: "Reading receipt…", else: "Save receipt"),
          :save,
          weight: 1
        )}
      </Row>
    </Column>
    """
  end

  # Once there's a code: what it says. Before: a button to scan it.
  defp qr_section(%{receipt: %Transaction{qr_content: nil}, reading: false}) do
    ActionButton.button(nil, "Scan the receipt's QR code", :scan_qr, style: :secondary)
  end

  defp qr_section(%{receipt: %Transaction{qr_content: nil}}), do: []

  defp qr_section(%{receipt: receipt}) do
    ~MOB"""
    <Box
      background={:surface}
      border_color={:border}
      border_width={1}
      corner_radius={16}
      padding={12}
      fill_width={true}
    >
      <Column fill_width={true}>
        <Row fill_width={true} align={:center}>
          {KraBadge.badge(receipt)}
          <Text
            text={qr_heading(receipt)}
            text_size={14}
            font_weight="semibold"
            text_color={:on_surface}
          />
        </Row>
        <Spacer size={4} />
        <Text
          :if={receipt.seller_pin}
          text={"Seller KRA PIN: #{receipt.seller_pin}"}
          text_size={13}
          text_color={:muted}
        />
        <Text
          :if={receipt.invoice_number}
          text={"Receipt no.: #{receipt.invoice_number}"}
          text_size={13}
          text_color={:muted}
          max_lines={2}
        />
      </Column>
    </Box>
    """
  end

  defp qr_heading(%{source: "etims"}), do: "KRA eTIMS receipt"
  defp qr_heading(%{source: "tims"}), do: "KRA TIMS receipt"
  defp qr_heading(%{source: "kra"}), do: "KRA link"
  defp qr_heading(_receipt), do: "QR code"

  # While the photo is read, a card says so where the photo will be.
  defp photo_section(%{reading: true}) do
    ~MOB"""
    <Box
      background={:surface}
      border_color={:border}
      border_width={1}
      corner_radius={16}
      padding={14}
      fill_width={true}
    >
      <Column fill_width={true}>
        <Text
          text="Reading receipt…"
          text_size={15}
          font_weight="semibold"
          text_color={:on_surface}
        />
        <Spacer size={2} />
        <Text
          text="Finding the vendor, date and total in your photo."
          text_size={12}
          text_color={:muted}
        />
      </Column>
    </Box>
    """
  end

  defp photo_section(%{receipt: %Transaction{photo_path: nil}}) do
    ActionButton.button("add", "Add receipt photo", :take_photo, style: :secondary)
  end

  defp photo_section(%{receipt: receipt}) do
    ~MOB"""
    <Column fill_width={true}>
      <Image
        src={Photos.path(receipt.photo_path)}
        height={220}
        fill_width={true}
        corner_radius={16}
        content_mode={:fill}
        on_tap={{self(), :view_photo}}
        accessibility_label="View the receipt photo"
      />
      <Spacer size={8} />
      <Row fill_width={true} gap={8}>
        {ActionButton.button("refresh", "Retake", :take_photo, style: :secondary, weight: 1)}
        {ActionButton.button("trash", "Remove", :remove_photo, style: :secondary, weight: 1)}
      </Row>
    </Column>
    """
  end

  @impl Mob.Screen
  def handle_info({:change, key, value}, socket) when key in @text_fields do
    {:noreply,
     socket
     |> Mob.Socket.assign(key, value)
     |> Mob.Socket.assign(:touched, MapSet.put(socket.assigns.touched, key))}
  end

  # The category is a choice, not something to type: offer them in a sheet.
  def handle_info({:tap, :pick_category}, socket) do
    buttons =
      @categories
      |> Enum.with_index()
      |> Enum.map(fn {category, i} -> [label: category, action: :"category_#{i}"] end)

    {:noreply,
     Mob.Alert.action_sheet(socket,
       title: "Category",
       buttons: buttons ++ [[label: "Cancel", style: :cancel]]
     )}
  end

  def handle_info({:alert, action}, socket) when is_map_key(@category_actions, action) do
    {:noreply, Mob.Socket.assign(socket, :category, Map.fetch!(@category_actions, action))}
  end

  # ── The photo ─────────────────────────────────────────────────────────────

  def handle_info({:tap, :take_photo}, socket), do: {:noreply, Native.request_camera(socket)}

  def handle_info({:permission, :camera, :granted}, socket),
    do: {:noreply, Native.take_photo(socket)}

  def handle_info({:permission, :camera, _denied}, socket) do
    {:noreply, Native.toast(socket, "Camera access is off. Allow it in Settings to add photos.")}
  end

  def handle_info({:camera, :photo, %{path: tmp}}, socket),
    do: {:noreply, read_photo(socket, tmp)}

  def handle_info({:ocr, :result, json}, socket) do
    data = MobOcr.decode(json)
    text = data["text"] || ""
    fields = OcrParser.parse(text)

    {:noreply,
     socket
     |> replace_photo(Photos.name(data["path"]))
     |> update_receipt(&%{&1 | ocr_text: text, source: photo_source(&1)})
     |> attach_qr(data["qr"])
     |> fill_untouched(fields, socket.assigns.from_kra)
     |> Mob.Socket.assign(reading: false)
     |> put_photo_notice(fields)}
  end

  # The photo may have been saved even if reading it failed.
  def handle_info({:ocr, :error, json}, socket) do
    data = MobOcr.decode(json)

    socket =
      case data["path"] do
        path when is_binary(path) ->
          socket
          |> replace_photo(Photos.name(path))
          |> update_receipt(&%{&1 | source: "photo"})

        nil ->
          socket
      end

    notice =
      if data["message"] == "not_available",
        do: "Reading photos isn't available on this phone. Fill in the details below.",
        else:
          "Couldn't read the text in this photo. Fill in the details below, or retake it in better light."

    {:noreply, Mob.Socket.assign(socket, reading: false, notice: notice)}
  end

  # ── The QR code and KRA ───────────────────────────────────────────────────

  def handle_info({:tap, :scan_qr}, socket), do: {:noreply, Native.scan_qr(socket)}

  def handle_info({:scan, :result, %{value: value}}, socket) when is_binary(value) do
    {:noreply,
     socket
     |> attach_qr(value)
     |> fill_untouched(QrParser.parse(value), socket.assigns.from_kra)}
  end

  def handle_info({:scan, :permission_denied}, socket) do
    {:noreply, Native.toast(socket, "Camera access is off. Allow it in Settings to scan.")}
  end

  # KRA's record fills what the person hasn't typed, and those fields are
  # then KRA's: a photo read later won't change them.
  def handle_info({:kra, :result, details}, socket) do
    filled =
      [date: :date, vendor: :vendor, amount: :amount_cents, description: :description]
      |> Enum.filter(fn {_field, key} -> details[key] end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.reject(&(&1 in socket.assigns.touched))

    # KRA returning the receipt is what makes it verified.
    verified_at = DateTime.truncate(DateTime.utc_now(), :second)

    {:noreply,
     socket
     |> update_receipt(&%{&1 | verified_at: verified_at})
     |> fill_untouched(details, MapSet.new())
     |> Mob.Socket.assign(
       from_kra: MapSet.union(socket.assigns.from_kra, MapSet.new(filled)),
       notice:
         "Verified with KRA and filled in from its record of this receipt. " <>
           "Check the details and pick a category."
     )}
  end

  # KRA answered, but has no record of this receipt (yet): sellers sometimes
  # send their receipts to KRA late.
  def handle_info({:kra, :error, :unrecognised}, socket) do
    {:noreply,
     Mob.Socket.assign(
       socket,
       :notice,
       "KRA has no record of this receipt yet. Fill in the details from the " <>
         "paper receipt. You can verify it later from the list."
     )}
  end

  def handle_info({:kra, :error, _reason}, socket) do
    {:noreply,
     Mob.Socket.assign(
       socket,
       :notice,
       "Couldn't get this receipt from KRA. Check your connection, and fill in " <>
         "the details from the paper receipt. You can verify it later from the list."
     )}
  end

  def handle_info({:tap, :remove_photo}, socket) do
    {:noreply,
     socket
     |> replace_photo(nil)
     |> update_receipt(&%{&1 | ocr_text: nil, source: "manual"})
     |> Mob.Socket.assign(:notice, nil)}
  end

  # ── Saving ────────────────────────────────────────────────────────────────

  # Saving half-read would race the reading; the button says to wait.
  def handle_info({:tap, :save}, %{assigns: %{reading: true}} = socket), do: {:noreply, socket}

  def handle_info({:tap, :save}, socket) do
    case build_attrs(socket.assigns) do
      {:ok, attrs} -> save(socket, attrs)
      {:error, errors} -> {:noreply, Mob.Socket.assign(socket, :errors, errors)}
    end
  end

  def handle_info({:tap, :delete}, socket) do
    {:noreply,
     Mob.Alert.alert(socket,
       title: "Delete this receipt?",
       message: "#{socket.assigns.receipt.vendor} will be removed from your expenses.",
       buttons: [
         [label: "Delete", style: :destructive, action: :confirm_delete],
         [label: "Cancel", style: :cancel]
       ]
     )}
  end

  def handle_info({:alert, :confirm_delete}, socket) do
    {:ok, _} = Transactions.delete_transaction(socket.assigns.receipt)
    {:noreply, back_to_list(socket)}
  end

  def handle_info({:tap, :view_photo}, socket) do
    {:noreply, Mob.Socket.assign(socket, :viewing_photo, true)}
  end

  def handle_info({:tap, :close_photo}, socket) do
    {:noreply, Mob.Socket.assign(socket, :viewing_photo, false)}
  end

  def handle_info({:tap, :save_photo}, socket) do
    {:noreply, Native.save_to_gallery(socket, Photos.path(socket.assigns.receipt.photo_path))}
  end

  def handle_info({:storage, :saved_to_library, _path}, socket) do
    {:noreply, Native.toast(socket, "Saved to your phone's gallery")}
  end

  def handle_info({:storage, :error, :save_to_library, _reason}, socket) do
    {:noreply, Native.toast(socket, "Couldn't save the photo to your gallery")}
  end

  # Backing out leaves no orphan photo behind, and a saved receipt keeps
  # the photo it had.
  def handle_info({:tap, :back}, socket) do
    %{receipt: %{photo_path: photo}, saved_photo: saved_photo} = socket.assigns
    if photo != saved_photo, do: Photos.delete(photo)
    {:noreply, Mob.Socket.pop_screen(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp save(socket, attrs) do
    result =
      case socket.assigns.receipt do
        %Transaction{id: nil} ->
          Transactions.create_transaction(attrs)

        # The draft has been changed in memory (a new photo, say), so compare
        # the attrs with the row as it's saved, or Ecto would see no change.
        %Transaction{id: id} ->
          Transactions.update_transaction(Transactions.get_transaction!(id), attrs)
      end

    case result do
      {:ok, saved} ->
        # A replaced photo goes once the new one is safely saved.
        old = socket.assigns.saved_photo
        if old not in [nil, saved.photo_path], do: Photos.delete(old)
        {:noreply, back_to_list(socket)}

      {:error, :paid} ->
        {:noreply, Native.toast(socket, "This one has been paid, so it can't change")}

      {:error, changeset} ->
        {:noreply, Mob.Socket.assign(socket, :errors, changeset_errors(changeset))}
    end
  end

  # Reset rather than pop, so the list mounts again with the new totals.
  defp back_to_list(socket) do
    Mob.Socket.reset_to(socket, RisitiApp.Screens.ReceiptsScreen, %{}, transition: :pop)
  end

  @doc false
  # Turns the form's inputs into changeset attrs, catching the two fields
  # (date and amount) that need parsing before Ecto sees them.
  def build_attrs(assigns) do
    date_result = Date.from_iso8601(String.trim(assigns.date))
    amount_result = Transactions.parse_amount(assigns.amount)

    errors =
      %{}
      |> put_error_if(match?({:error, _}, date_result), :date, "use the format 2026-09-23")
      |> put_error_if(amount_result == :error, :amount, "enter an amount like 1250 or 1,250.50")

    if errors == %{} do
      {:ok, date} = date_result
      {:ok, amount_cents} = amount_result

      {:ok,
       %{
         source: assigns.receipt.source,
         photo_path: assigns.receipt.photo_path,
         ocr_text: assigns.receipt.ocr_text,
         qr_content: assigns.receipt.qr_content,
         seller_pin: assigns.receipt.seller_pin,
         branch_id: assigns.receipt.branch_id,
         invoice_number: assigns.receipt.invoice_number,
         verify_url: assigns.receipt.verify_url,
         verified_at: assigns.receipt.verified_at,
         date: date,
         vendor: assigns.vendor,
         description: assigns.description,
         amount_cents: amount_cents,
         category: assigns.category
       }}
    else
      {:error, errors}
    end
  end

  # Starts reading a photo the camera just took. MobOcr saves the upright,
  # shrunk copy we keep at a new path, and deletes the camera's file.
  defp read_photo(socket, tmp) do
    # What KRA said stays on show while the photo is read.
    notice = if kra_answered?(socket), do: socket.assigns.notice, else: nil

    socket
    |> Mob.Socket.assign(reading: true, notice: notice)
    |> Native.process_photo(tmp, Photos.new_path())
  end

  defp kra_answered?(socket), do: socket.assigns.receipt.verified_at != nil

  defp put_photo_notice(socket, fields) do
    if kra_answered?(socket),
      do: socket,
      else: Mob.Socket.assign(socket, :notice, ocr_notice(fields))
  end

  # A photo of a receipt found by its QR code keeps the QR code's source.
  defp photo_source(%Transaction{source: source}) when source in ["manual", "photo"], do: "ocr"
  defp photo_source(%Transaction{source: source}), do: source

  # A QR code already on the draft wins: it was scanned on purpose.
  defp attach_qr(socket, qr) when is_binary(qr) and qr != "" do
    case socket.assigns.receipt do
      %Transaction{qr_content: nil} = receipt ->
        socket
        |> Mob.Socket.assign(:receipt, Transactions.put_qr(receipt, qr))
        |> duplicate_check()
        |> lookup_kra()

      _ ->
        socket
    end
  end

  defp attach_qr(socket, _qr), do: socket

  # Only eTIMS and TIMS links lead to a page with the receipt on it.
  defp lookup_kra(%{assigns: %{receipt: receipt}} = socket) do
    if Transactions.verifiable?(receipt) do
      socket
      |> Mob.Socket.assign(:notice, "Getting this receipt's details from KRA…")
      |> Native.lookup_kra(receipt.verify_url)
    else
      socket
    end
  end

  # Says so now, rather than at Save, when this code is already on another
  # saved receipt. (The unique index would refuse the save anyway.)
  defp duplicate_check(%{assigns: %{receipt: %Transaction{qr_content: nil}}} = socket), do: socket

  defp duplicate_check(%{assigns: %{receipt: receipt}} = socket) do
    case Transactions.find_by_qr(receipt.qr_content) do
      %Transaction{id: id} = existing when id != receipt.id ->
        Mob.Socket.assign(socket, :errors, %{
          base:
            "You already saved this receipt (#{existing.vendor}, " <>
              "#{Calendar.strftime(existing.date, "%d %b %Y")})."
        })

      _ ->
        socket
    end
  end

  # Points the draft at a new photo file. The file it pointed at before is
  # deleted, unless it's the saved receipt's photo: that one goes on save,
  # so backing out of an edit leaves the receipt as it was.
  defp replace_photo(socket, name) do
    %{receipt: receipt, saved_photo: saved_photo} = socket.assigns
    if receipt.photo_path not in [nil, saved_photo, name], do: Photos.delete(receipt.photo_path)
    update_receipt(socket, &%{&1 | photo_path: name})
  end

  defp update_receipt(socket, fun),
    do: Mob.Socket.assign(socket, :receipt, fun.(socket.assigns.receipt))

  # What was read or fetched fills a field only if the person hasn't typed
  # in it, and it isn't one of the `protected` ones (KRA's).
  defp fill_untouched(socket, fields, protected) do
    date = fields[:date]
    cents = fields[:amount_cents]

    candidates = [
      date: date && Date.to_iso8601(date),
      vendor: fields[:vendor],
      description: fields[:description],
      amount: cents && Transactions.amount_input(cents)
    ]

    skip = MapSet.union(socket.assigns.touched, protected)

    Enum.reduce(candidates, socket, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> if key in skip, do: acc, else: Mob.Socket.assign(acc, key, value)
    end)
  end

  # Says what was found, and what wasn't, so the person knows what to check.
  defp ocr_notice(fields) do
    names = [vendor: "vendor", date: "date", amount_cents: "total"]
    {found, missing} = Enum.split_with(names, fn {key, _} -> fields[key] end)
    found = Enum.map(found, &elem(&1, 1))
    missing = Enum.map(missing, &elem(&1, 1))

    cond do
      found == [] ->
        "Couldn't find the details in this photo. Fill them in below."

      missing == [] ->
        "Read the #{Enum.join(found, ", ")} from the photo. Check them against the receipt."

      true ->
        "Read the #{Enum.join(found, ", ")} from the photo. Couldn't find the " <>
          "#{Enum.join(missing, " or ")}, so please fill it in."
    end
  end

  defp put_error_if(errors, true, field, message), do: Map.put(errors, field, message)
  defp put_error_if(errors, false, _field, _message), do: errors

  # One message per field, in words: %{vendor: "Vendor can't be blank"}.
  defp changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.reduce(%{}, fn
      {:amount_cents, [message | _]}, acc -> Map.put(acc, :amount, "Amount #{message}")
      {:qr_content, [message | _]}, acc -> Map.put(acc, :base, message)
      {field, [message | _]}, acc -> Map.put(acc, field, "#{humanize(field)} #{message}")
    end)
  end

  defp humanize(field), do: field |> Atom.to_string() |> String.capitalize()
end
