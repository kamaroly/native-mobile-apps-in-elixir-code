defmodule RisitiApp.Remote do
  @moduledoc """
  Server records (JSON from `RisitiApp.Api`) as the structs the screens
  already draw, so the approver's list can reuse `TransactionItem`.

  They're never saved on this phone: `id` is the server's id, and there are
  no local files. A photo or attachment downloads when it's opened.
  """

  alias RisitiApp.Transactions.{Attachment, Transaction}

  @doc "A transaction from the server, its sender's name, and whether it has a photo."
  @spec transaction(map()) :: %{
          transaction: Transaction.t(),
          from: String.t(),
          has_photo: boolean()
        }
  def transaction(json) do
    %{
      transaction: %Transaction{
        id: json["id"],
        remote_id: json["id"],
        client_id: json["client_id"],
        type: json["type"] || "expense",
        pay_to: json["pay_to"],
        status: json["status"] || "pending",
        date: Date.from_iso8601!(json["date"]),
        vendor: json["vendor"],
        description: json["description"],
        amount_cents: json["amount_cents"],
        category: json["category"],
        method: json["method"],
        phone: json["phone"],
        till_number: json["till_number"],
        paybill_number: json["paybill_number"],
        account_number: json["account_number"],
        source: json["source"] || "manual",
        seller_pin: json["seller_pin"],
        invoice_number: json["invoice_number"],
        verify_url: json["verify_url"],
        decision_note: json["decision_note"],
        attachments: Enum.map(json["attachments"] || [], &attachment/1)
      },
      from: who(json["submitted_by"]),
      has_photo: json["has_photo"] == true
    }
  end

  defp attachment(json),
    do: %Attachment{
      id: json["id"],
      name: json["name"],
      content_type: json["content_type"],
      size: json["size"]
    }

  defp who(%{"name" => name}) when is_binary(name) and name != "", do: name
  defp who(%{"phone" => phone}) when is_binary(phone), do: phone
  defp who(_person), do: "someone"
end
