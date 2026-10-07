defmodule RisitiWeb.ExportController do
  @moduledoc """
  The export file (`Risiti.Expenses.Export`), for people who may export
  (`transactions:export_transactions`). What's exported is marked, so the
  next export can leave it out.
  """

  use RisitiWeb, :controller

  alias Risiti.Accounts.Permissions
  alias Risiti.Expenses.{Export, Transaction}

  def download(conn, params) do
    user = conn.assigns.current_user

    with true <- Permissions.can?(user, "transactions:export_transactions"),
         {:ok, from} <- Date.from_iso8601(params["from"] || ""),
         {:ok, to} <- Date.from_iso8601(params["to"] || ""),
         format when not is_nil(format) <- format(params["format"]) do
      unexported_only? = params["unexported_only"] == "true"
      transactions = Transaction.for_export!(from, to, unexported_only?, actor: user)
      csv = Export.build(format, transactions)
      Enum.each(transactions, &Transaction.mark_exported!(&1, actor: user))

      send_download(conn, {:binary, csv},
        filename: "risiti-#{format}-#{from}-to-#{to}.csv",
        content_type: "text/csv"
      )
    else
      false ->
        conn
        |> put_flash(:error, "You can't export transactions")
        |> redirect(to: ~p"/transactions")

      _bad_params ->
        conn
        |> put_flash(:error, "Choose the dates and a format")
        |> redirect(to: ~p"/transactions")
    end
  end

  defp format(id),
    do: Enum.find_value(Export.formats(), fn {key, _} -> if "#{key}" == id, do: key end)
end
