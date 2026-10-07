defmodule Risiti.Expenses do
  @moduledoc """
  A team's spending: its categories now, its transactions soon. Everything
  here lives in the team's own schema.
  """

  use Ash.Domain, otp_app: :risiti

  resources do
    resource Risiti.Expenses.Category
  end
end
