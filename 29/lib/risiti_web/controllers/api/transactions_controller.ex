defmodule RisitiWeb.Api.TransactionsController do
  @moduledoc """
  The signed-in person's own transactions.

  Each is sent keyed by the phone's own id (`client_id`), so the phone can
  send again after a dropped connection without making copies. The receipt
  photo and any attachments come as multipart files alongside the fields;
  an attachment the transaction already has (same name and size) isn't
  added twice.
  """

  use RisitiWeb, :controller

  alias Risiti.Expenses
  alias Risiti.Expenses.{Attachment, Category, PaymentMethod, Storage, Transaction}
  alias Risiti.Expenses.TransactionType
  alias RisitiWeb.Api.JSON

  @fields ~w(type pay_to date vendor description amount_cents tax_cents category method phone
             till_number paybill_number account_number source qr_content seller_pin branch_id
             invoice_number verify_url verified_at ocr_text)

  @doc "The fixed types and payment methods, and the team's categories."
  def catalog(conn, _params) do
    user = conn.assigns.current_user

    json(conn, %{
      types:
        Enum.map(TransactionType.all(), fn type ->
          %{
            code: type.code,
            name: type.name,
            description: type.description,
            payable: type.payable?
          }
        end),
      methods: Enum.map(PaymentMethod.all(), &Map.take(&1, [:code, :name, :required_fields])),
      categories:
        [actor: user] |> Category.list_categories!() |> Enum.map(& &1.name) |> Enum.sort()
    })
  end

  def index(conn, _params) do
    user = conn.assigns.current_user

    transactions = Transaction.mine!(actor: user, load: [:attachments, :user])
    json(conn, %{transactions: Enum.map(transactions, &JSON.transaction/1)})
  end

  def put(conn, %{"client_id" => client_id} = params) do
    user = conn.assigns.current_user
    attrs = params |> Map.take(@fields) |> Map.put("client_id", client_id)

    with {:ok, attrs} <- with_photo(attrs, params["photo"], user),
         {:ok, stored} <- store_all(params["attachments"], user),
         {:ok, transaction} <- save(attrs, stored, user) do
      transaction = Ash.load!(transaction, [:attachments, :user], actor: user)
      json(conn, %{transaction: JSON.transaction(transaction)})
    else
      {:error, error} -> invalid(conn, error)
    end
  end

  @doc """
  Withdraws a transaction deleted on the phone, while it still waits for a
  decision, with its files. One the server never had counts as deleted.
  """
  def delete(conn, %{"client_id" => client_id}) do
    user = conn.assigns.current_user

    case Expenses.own_transaction!(client_id, actor: user, load: [:attachments]) do
      nil ->
        send_resp(conn, 204, "")

      transaction ->
        case Transaction.withdraw(transaction, actor: user) do
          :ok ->
            files = [transaction.photo_file | Enum.map(transaction.attachments, & &1.file)]
            Storage.delete(user.current_team, files)
            send_resp(conn, 204, "")

          {:error, error} ->
            invalid(conn, error)
        end
    end
  end

  # The transaction and its new attachments are saved together, or not at all.
  defp save(attrs, stored, user) do
    Ash.transact(Transaction, fn ->
      with {:ok, transaction} <- Expenses.sync_transaction(attrs, actor: user) do
        existing =
          transaction
          |> Ash.load!(:attachments, actor: user)
          |> Map.fetch!(:attachments)
          |> MapSet.new(&{&1.name, &1.size})

        stored
        |> Enum.reject(&MapSet.member?(existing, {&1.name, &1.size}))
        |> Enum.each(
          &Attachment.attach!(Map.put(&1, :transaction_id, transaction.id), actor: user)
        )

        transaction
      end
    end)
  end

  defp with_photo(attrs, %Plug.Upload{} = upload, user) do
    case Storage.store(user.current_team, upload) do
      {:ok, %{file: file}} -> {:ok, Map.put(attrs, "photo_file", file)}
      {:error, reason} -> {:error, %{photo: upload_error(reason)}}
    end
  end

  defp with_photo(attrs, _no_photo, _user), do: {:ok, attrs}

  # `attachments[]` arrives as a list.
  defp store_all(nil, _user), do: {:ok, []}

  defp store_all(uploads, user) when is_list(uploads) do
    Enum.reduce_while(uploads, {:ok, []}, fn upload, {:ok, acc} ->
      case Storage.store(user.current_team, upload) do
        {:ok, stored} ->
          {:cont, {:ok, [Map.put(stored, :name, upload.filename) | acc]}}

        {:error, reason} ->
          {:halt, {:error, %{attachments: "#{upload.filename}: #{upload_error(reason)}"}}}
      end
    end)
  end

  # ── Files ─────────────────────────────────────────────────────────────────

  @doc "A transaction's receipt photo, for anyone who may see the transaction."
  def photo(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, transaction} <- Ash.get(Transaction, id, actor: user),
         path when is_binary(path) <- Storage.path(user.current_team, transaction.photo_file) do
      send_download(conn, {:file, path},
        disposition: :inline,
        filename: "receipt#{Path.extname(path)}"
      )
    else
      _ -> not_found(conn)
    end
  end

  @doc "An attachment, for anyone who may see its transaction."
  def attachment(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, attachment} <- Ash.get(Attachment, id, actor: user),
         {:ok, _visible} <- Ash.get(Transaction, attachment.transaction_id, actor: user),
         path when is_binary(path) <- Storage.path(user.current_team, attachment.file) do
      send_download(conn, {:file, path}, disposition: :inline, filename: attachment.name)
    else
      _ -> not_found(conn)
    end
  end

  # ── Errors ────────────────────────────────────────────────────────────────

  defp invalid(conn, %Ash.Error.Forbidden{}),
    do: conn |> put_status(403) |> json(%{error: "You can't change that transaction"})

  defp invalid(conn, %{} = errors) when not is_struct(errors),
    do: conn |> put_status(422) |> json(%{errors: errors})

  defp invalid(conn, error), do: conn |> put_status(422) |> json(%{errors: JSON.errors(error)})

  defp not_found(conn), do: conn |> put_status(404) |> json(%{error: "Not found"})

  defp upload_error(:unsupported), do: "only images and PDFs"
  defp upload_error(:too_large), do: "over 10 MB"
  defp upload_error(_reason), do: "couldn't be saved"
end
