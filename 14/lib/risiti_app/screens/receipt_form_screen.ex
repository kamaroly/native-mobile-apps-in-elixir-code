defmodule RisitiApp.Screens.ReceiptFormScreen do
  @moduledoc """
  Add an expense by hand, or edit a saved one.

  Mount params:

    * `%{photo: tmp_path}` — a photo was just taken: keep it, and fill in
      the rest by hand.
    * `%{id: id}` — edit a saved transaction.
    * `%{}` — enter an expense by hand.
  """

  use Mob.Screen

  alias RisitiApp.Transactions
  alias RisitiApp.Receipts.Photos
  alias RisitiApp.Components.{ActionButton, FormField}
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
        %{id: id} ->
          Transactions.get_transaction!(id)

        %{photo: tmp} ->
          %Transaction{
            date: Transactions.today(),
            category: "Other",
            source: "photo",
            photo_path: Photos.keep(tmp)
          }

        _ ->
          %Transaction{date: Transactions.today(), category: "Other"}
      end

    socket =
      Mob.Socket.assign(socket,
        receipt: receipt,
        date: Date.to_iso8601(receipt.date),
        vendor: receipt.vendor || "",
        description: receipt.description || "",
        amount: Transactions.amount_input(receipt.amount_cents),
        category: receipt.category,
        errors: %{}
      )

    {:ok, socket}
  end

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Column background={:background} fill_height={true}>
      <Header title={if @receipt.id, do: "Edit receipt", else: "New receipt"} show_back={true} />
      <Scroll weight={1}>
        <Column padding_left={22} padding_right={22}>
          <Image
            :if={@receipt.photo_path}
            src={Photos.path(@receipt.photo_path)}
            height={220}
            fill_width={true}
            corner_radius={16}
            content_mode={:fill}
          />
          <Spacer :if={@receipt.photo_path} size={16} />
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
        </Column>
      </Scroll>
      <Row padding={14} gap={8}>
        {if @receipt.id,
          do: ActionButton.button("trash", "Delete", :delete, style: :danger, width: 120)}
        {ActionButton.button("check", "Save receipt", :save, weight: 1)}
      </Row>
    </Column>
    """
  end

  @impl Mob.Screen
  def handle_info({:change, key, value}, socket) when key in @text_fields do
    {:noreply, Mob.Socket.assign(socket, key, value)}
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

  # Backing out of a new receipt leaves no orphan photo behind.
  def handle_info({:tap, :back}, socket) do
    if socket.assigns.receipt.id == nil, do: Photos.delete(socket.assigns.receipt.photo_path)
    {:noreply, Mob.Socket.pop_screen(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp save(socket, attrs) do
    result =
      case socket.assigns.receipt do
        %Transaction{id: nil} -> Transactions.create_transaction(attrs)
        receipt -> Transactions.update_transaction(receipt, attrs)
      end

    case result do
      {:ok, _saved} ->
        {:noreply, back_to_list(socket)}

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
      {field, [message | _]}, acc -> Map.put(acc, field, "#{humanize(field)} #{message}")
    end)
  end

  defp humanize(field), do: field |> Atom.to_string() |> String.capitalize()
end
