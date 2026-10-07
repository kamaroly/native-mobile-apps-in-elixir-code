defmodule Risiti.Expenses.Transaction.Actions.Sync do
  @moduledoc """
  Saves a transaction sent from a phone: submits it the first time its
  `client_id` is seen, updates the actor's own one after that, so a resend
  never makes a copy.
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Changes.InvalidArgument
  alias Risiti.Expenses
  alias Risiti.Expenses.Transaction

  @impl true
  def run(%{arguments: %{attrs: attrs}}, _opts, context) do
    opts = Ash.Context.to_opts(context)

    case client_id(attrs) do
      nil ->
        {:error, InvalidArgument.exception(field: :client_id, message: "is required")}

      client_id ->
        case Expenses.own_transaction(client_id, opts) do
          {:ok, nil} ->
            Transaction.submit(attrs, opts)

          {:ok, transaction} ->
            Transaction.update_from_phone(
              transaction,
              Map.drop(attrs, [:client_id, "client_id"]),
              opts
            )

          error ->
            error
        end
    end
  end

  defp client_id(%{"client_id" => client_id}) when not is_nil(client_id), do: to_string(client_id)
  defp client_id(%{client_id: client_id}) when not is_nil(client_id), do: to_string(client_id)
  defp client_id(_attrs), do: nil
end
