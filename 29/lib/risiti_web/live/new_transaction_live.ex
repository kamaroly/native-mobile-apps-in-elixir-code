defmodule RisitiWeb.NewTransactionLive do
  @moduledoc """
  An expense added on the web, with its receipt. The receipt is read as
  soon as it's uploaded (`Risiti.Expenses.ReceiptReader`), and what's found
  fills the fields the person hasn't typed in. It's sent like a phone's,
  with a `client_id` of its own, and waits for approval the same way.
  """

  use RisitiWeb, :live_view

  alias Risiti.Expenses
  alias Risiti.Expenses.{Category, OcrParser, QrParser, ReceiptReader, Storage, Transaction}

  @fields ~w(date vendor amount category description)

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    socket
    |> assign(
      categories:
        [actor: user] |> Category.list_categories!() |> Enum.map(& &1.name) |> Enum.sort(),
      params: %{"date" => Date.to_iso8601(Expenses.today())},
      receipt: %{},
      reading: false,
      errors: %{}
    )
    |> allow_upload(:receipt,
      accept: ~w(.jpg .jpeg .png .pdf),
      max_entries: 1,
      max_file_size: 10_000_000,
      auto_upload: true,
      progress: &handle_progress/3
    )
    |> then(&{:ok, &1})
  end

  def handle_event("change", %{"transaction" => params}, socket),
    do: {:noreply, assign(socket, params: Map.take(params, @fields))}

  def handle_event("save", %{"transaction" => params}, socket) do
    user = socket.assigns.current_user
    params = Map.take(params, @fields)

    attrs =
      socket.assigns.receipt
      |> Map.merge(%{
        "client_id" => "web-" <> Ecto.UUID.generate(),
        "type" => "expense",
        "date" => params["date"],
        "vendor" => params["vendor"],
        "category" => params["category"],
        "description" => params["description"],
        "amount_cents" => amount_cents(params["amount"])
      })

    case Transaction.submit(attrs, actor: user) do
      {:ok, _transaction} ->
        {:noreply,
         socket |> put_flash(:info, "Sent for approval") |> push_navigate(to: ~p"/transactions")}

      {:error, error} ->
        {:noreply, assign(socket, params: params, errors: RisitiWeb.Api.JSON.errors(error))}
    end
  end

  # The upload is done: keep the file, read it, and fill in what we found.
  def handle_progress(:receipt, entry, socket) when entry.done? do
    tenant = socket.assigns.current_user.current_team

    stored =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        upload = %Plug.Upload{
          path: path,
          filename: entry.client_name,
          content_type: entry.client_type
        }

        {:ok, Storage.store(tenant, upload)}
      end)

    case stored do
      {:ok, %{file: file, content_type: type}} ->
        found = read(Storage.path(tenant, file), type)

        {:noreply,
         socket
         |> assign(receipt: Map.put(found.details, "photo_file", file))
         |> assign(
           params:
             Map.merge(found.fields, socket.assigns.params, fn _k, read, typed ->
               if blank?(typed), do: read, else: typed
             end)
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't keep that file")}
    end
  end

  def handle_progress(:receipt, _entry, socket), do: {:noreply, socket}

  # What the parsers found: form fields, and details kept with the transaction.
  defp read(path, content_type) do
    case ReceiptReader.read(path, content_type) do
      {:ok, %{text: text, qr: qr}} ->
        ocr = OcrParser.parse(text)
        from_qr = if qr, do: QrParser.parse(qr), else: %{}

        %{
          fields:
            %{
              "vendor" => ocr.vendor,
              "date" => ocr.date && Date.to_iso8601(ocr.date),
              "amount" => ocr.amount_cents && Expenses.format_amount(ocr.amount_cents)
            }
            |> Map.reject(fn {_k, v} -> is_nil(v) end),
          details:
            %{
              "ocr_text" => text,
              "source" => if(qr, do: from_qr.source, else: "ocr"),
              "qr_content" => qr,
              "seller_pin" => from_qr[:seller_pin],
              "branch_id" => from_qr[:branch_id],
              "invoice_number" => from_qr[:invoice_number],
              "verify_url" => from_qr[:verify_url]
            }
            |> Map.reject(fn {_k, v} -> is_nil(v) end)
        }

      {:error, _reason} ->
        %{fields: %{}, details: %{}}
    end
  end

  defp amount_cents(text) do
    case Expenses.parse_amount(text) do
      {:ok, cents} -> cents
      :error -> nil
    end
  end

  defp blank?(value), do: value in [nil, ""]

  defp form_field(:amount_cents), do: :amount
  defp form_field(field), do: field

  def render(assigns) do
    # The amount is typed in shillings; its errors come back for amount_cents.
    errors = for {field, message} <- assigns.errors, do: {form_field(field), {message, []}}
    assigns = assign(assigns, form: to_form(assigns.params, as: :transaction, errors: errors))

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} can_decide={@can_decide}>
      <.header>New expense</.header>

      <.form for={@form} id="new-transaction" phx-change="change" phx-submit="save" class="space-y-4">
        <div class="space-y-2">
          <label class="label">Receipt (photo or PDF)</label>
          <.live_file_input upload={@uploads.receipt} class="file-input file-input-bordered w-full" />
          <p :for={entry <- @uploads.receipt.entries} class="text-sm">
            {entry.client_name} · {entry.progress}%
          </p>
          <p :if={@receipt["photo_file"]} id="receipt-read" class="text-sm text-success">
            Receipt kept{if @receipt["ocr_text"], do: " and read: check what was filled in"}.
          </p>
        </div>

        <.input field={@form[:date]} type="date" label="Date" />
        <.input field={@form[:vendor]} label="Vendor" />
        <.input
          field={@form[:amount]}
          label="Amount (Ksh)"
        />
        <.input
          field={@form[:category]}
          type="select"
          label="Category"
          prompt="Choose a category"
          options={@categories}
        />
        <.input field={@form[:description]} type="textarea" label="Description" />
        <.button>Send for approval</.button>
      </.form>
    </Layouts.app>
    """
  end
end
