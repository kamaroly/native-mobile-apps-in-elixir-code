defmodule RisitiApp.Repo.Migrations.AddClaimsAndStatusToTransactions do
  use Ecto.Migration

  def up do
    alter table(:transactions) do
      # Refunds and payment requests: who is paid, and how.
      add :pay_to, :string
      add :method, :string
      add :phone, :string
      add :till_number, :string
      add :paybill_number, :string
      add :account_number, :string

      # pending -> approved | rejected, and for claims approved -> paid.
      add :status, :string, null: false, default: "pending"
      add :decision_note, :string
      add :decided_at, :utc_datetime
      add :paid_at, :utc_datetime

      # The phone's own id for the transaction; sync is keyed on it.
      add :client_id, :string
    end

    flush()

    # Receipts saved before this migration need a client id too. SQLite can
    # make 16 random bytes; written as hex they're as unique as a UUID.
    execute "UPDATE transactions SET client_id = lower(hex(randomblob(16))) WHERE client_id IS NULL"

    create unique_index(:transactions, [:client_id])
  end

  def down do
    drop index(:transactions, [:client_id])

    alter table(:transactions) do
      remove :pay_to
      remove :method
      remove :phone
      remove :till_number
      remove :paybill_number
      remove :account_number
      remove :status
      remove :decision_note
      remove :decided_at
      remove :paid_at
      remove :client_id
    end
  end
end
