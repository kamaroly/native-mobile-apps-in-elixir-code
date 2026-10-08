defmodule RisitiWeb.Api.JSON do
  @moduledoc """
  The JSON the phone reads. Amounts are integer cents, dates ISO 8601,
  types and statuses lowercase strings: the same as on the phone.
  """

  alias Risiti.Accounts.Permissions
  alias Risiti.Expenses.{Attachment, Transaction}

  # The phone's names for the permissions it acts on.
  @permissions %{
    approve: "transactions:approve_transactions",
    mark_paid: "transactions:mark_transactions_paid",
    list_all: "transactions:list_all_transactions",
    export: "transactions:export_transactions"
  }

  @doc "The signed-in person, their current team, and what they may do in it."
  def user(user) do
    team = user.current_team && Risiti.Accounts.team_for_tenant!(user.current_team)

    %{
      id: user.id,
      name: user.name,
      phone: user.phone,
      email: user.email && to_string(user.email),
      team: user.current_team,
      team_name: team && team.name,
      # "personal" (just them: no approvals, no claims) or "business".
      team_kind: team && team.kind,
      permissions:
        Map.new(@permissions, fn {key, name} -> {key, Permissions.can?(user, name)} end)
    }
  end

  @doc """
  A transaction, with the phone's `client_id` so the phone can match it to
  its own copy. The photo is a flag: the phone downloads it separately,
  and only if someone opens it.
  """
  def transaction(%Transaction{} = t) do
    %{
      id: t.id,
      client_id: t.client_id,
      type: t.type,
      pay_to: t.pay_to,
      status: t.status,
      date: t.date,
      vendor: t.vendor,
      description: t.description,
      amount_cents: t.amount_cents,
      tax_cents: t.tax_cents,
      category: t.category,
      method: t.method,
      phone: t.phone,
      till_number: t.till_number,
      paybill_number: t.paybill_number,
      account_number: t.account_number,
      source: t.source,
      seller_pin: t.seller_pin,
      invoice_number: t.invoice_number,
      verify_url: t.verify_url,
      verified_at: t.verified_at,
      has_photo: not is_nil(t.photo_file),
      decision_note: t.decision_note,
      decided_at: t.decided_at,
      paid_at: t.paid_at,
      attachments: loaded(t.attachments, &Enum.map(&1, fn a -> attachment(a) end)) || [],
      submitted_by: loaded(t.user, &person/1),
      inserted_at: t.inserted_at,
      updated_at: t.updated_at
    }
  end

  def attachment(%Attachment{} = a),
    do: %{id: a.id, name: a.name, content_type: a.content_type, size: a.size}

  @doc """
  Ash's validation errors as `%{field => message}`, each message short
  enough to follow the field's name: "till_number" => "must be 5 to 7
  digits".
  """
  def errors(%Ash.Error.Invalid{errors: errors}),
    do: errors |> Enum.flat_map(&field_errors/1) |> Map.new()

  def errors(other), do: %{base: inspect(other)}

  # The same short messages AshPhoenix gives forms. `Exception.message/1`
  # would add where the error came from, which is for logs, not people.
  defp field_errors(error) do
    if AshPhoenix.FormData.Error.impl_for(error) do
      error
      |> AshPhoenix.FormData.Error.to_form_error()
      |> List.wrap()
      |> Enum.map(fn {field, message, vars} -> {field || :base, interpolate(message, vars)} end)
    else
      [{Map.get(error, :field) || :base, Exception.message(error)}]
    end
  end

  # "must be at least %{min}" with min: 1 is "must be at least 1".
  defp interpolate(message, vars) do
    Enum.reduce(vars, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> text(value) end)
    end)
  end

  defp text(value) when is_list(value), do: Enum.map_join(value, ", ", &text/1)
  defp text(value), do: to_string(value)

  defp person(user), do: %{id: user.id, name: user.name, phone: user.phone}

  defp loaded(%Ash.NotLoaded{}, _fun), do: nil
  defp loaded(nil, _fun), do: nil
  defp loaded(value, fun), do: fun.(value)
end
