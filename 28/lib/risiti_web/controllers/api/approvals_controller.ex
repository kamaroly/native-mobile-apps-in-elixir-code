defmodule RisitiWeb.Api.ApprovalsController do
  @moduledoc """
  The approver's side of the phone: what waits for a decision (and approved
  claims waiting to be paid), and the decisions. The transaction's policies
  decide who may approve or mark paid.
  """

  use RisitiWeb, :controller

  alias Risiti.Accounts.Permissions
  alias Risiti.Expenses.Transaction
  alias RisitiWeb.Api.JSON

  def index(conn, _params) do
    user = conn.assigns.current_user

    if Permissions.can?(user, "transactions:approve_transactions") or
         Permissions.can?(user, "transactions:mark_transactions_paid") do
      transactions = Transaction.to_decide!(actor: user, load: [:attachments, :user])
      json(conn, %{transactions: Enum.map(transactions, &JSON.transaction/1)})
    else
      conn |> put_status(403) |> json(%{error: "You can't approve transactions"})
    end
  end

  def decide(conn, %{"id" => id, "decision" => decision} = params) do
    user = conn.assigns.current_user

    with {:ok, transaction} <- Ash.get(Transaction, id, actor: user),
         {:ok, transaction} <- decide(transaction, decision, params["note"], user) do
      transaction = Ash.load!(transaction, [:attachments, :user], actor: user)
      json(conn, %{transaction: JSON.transaction(transaction)})
    else
      error -> failed(conn, error)
    end
  end

  defp decide(t, "approve", note, user),
    do: Transaction.approve(t, blank_to_nil(note), actor: user)

  defp decide(t, "reject", note, user), do: Transaction.reject(t, blank_to_nil(note), actor: user)
  defp decide(t, "pay", _note, user), do: Transaction.mark_paid(t, actor: user)
  defp decide(_t, _decision, _note, _user), do: {:error, :unknown_decision}

  defp blank_to_nil(note) when is_binary(note),
    do: if(String.trim(note) == "", do: nil, else: String.trim(note))

  defp blank_to_nil(_note), do: nil

  defp failed(conn, {:error, %Ash.Error.Forbidden{}}),
    do: conn |> put_status(403) |> json(%{error: "You can't make that decision"})

  defp failed(conn, {:error, :unknown_decision}),
    do: conn |> put_status(422) |> json(%{error: "The decision must be approve, reject or pay"})

  defp failed(conn, {:error, %Ash.Error.Invalid{} = error}) do
    if Enum.any?(error.errors, &match?(%Ash.Error.Query.NotFound{}, &1)),
      do: conn |> put_status(404) |> json(%{error: "Not found"}),
      else: conn |> put_status(422) |> json(%{errors: JSON.errors(error)})
  end

  defp failed(conn, _error), do: conn |> put_status(404) |> json(%{error: "Not found"})
end
