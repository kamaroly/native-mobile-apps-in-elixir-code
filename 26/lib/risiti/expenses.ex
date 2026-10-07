defmodule Risiti.Expenses do
  @moduledoc """
  A team's spending: its transactions and the categories they're filed
  under. Everything here lives in the team's own schema.
  """

  use Ash.Domain, otp_app: :risiti, extensions: [AshPaperTrail.Domain]

  # Each resource's history (its `Version` resource) belongs to this domain too.
  paper_trail do
    include_versions?(true)
  end

  resources do
    resource Risiti.Expenses.Category

    resource Risiti.Expenses.Transaction do
      define :sync_transaction, action: :sync, args: [:attrs]
      define :own_transaction, action: :own, args: [:client_id], not_found_error?: false
    end
  end
end
