defmodule Risiti.Expenses.Transaction.Validations.PaymentDetails do
  @moduledoc """
  Each way of paying needs its own details (`PaymentMethod.required_fields/1`):
  a Kenyan mobile number for Send Money, a 5–7 digit till number, or a 5–7
  digit paybill number and an account number. Methods with no details
  (cash, card…) pass.
  """

  use Ash.Resource.Validation

  alias Risiti.Expenses.PaymentMethod

  @business_number ~r/^\d{5,7}$/
  @kenyan_mobile ~r/^\+254[17]\d{8}$/

  @impl true
  def validate(changeset, _opts, _context) do
    method = Ash.Changeset.get_attribute(changeset, :method)

    cond do
      is_nil(method) ->
        :ok

      method not in PaymentMethod.codes() ->
        {:error, field: :method, message: "is not a payment method we know"}

      true ->
        method
        |> PaymentMethod.required_fields()
        |> Enum.find_value(:ok, fn field ->
          case check(field, Ash.Changeset.get_attribute(changeset, field)) do
            :ok -> nil
            error -> error
          end
        end)
    end
  end

  defp check(:phone, value),
    do: format(value, @kenyan_mobile, :phone, "is not a Kenyan mobile number")

  defp check(field, value) when field in [:till_number, :paybill_number],
    do: format(value, @business_number, field, "must be 5 to 7 digits")

  defp check(field, value) do
    if value in [nil, ""],
      do: {:error, field: field, message: "is required for this payment method"},
      else: :ok
  end

  defp format(value, regex, field, message) do
    if is_binary(value) and value =~ regex,
      do: :ok,
      else: {:error, field: field, message: message}
  end
end
