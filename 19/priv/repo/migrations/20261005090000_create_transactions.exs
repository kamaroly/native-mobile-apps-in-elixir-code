defmodule RisitiApp.Repo.Migrations.CreateTransactions do
  use Ecto.Migration

  def change do
    create table(:transactions) do
      # "expense" for now; refunds and payment requests come later.
      add :type, :string, null: false, default: "expense"
      add :date, :date, null: false
      add :vendor, :string, null: false
      add :description, :string
      # Whole cents: Ksh 3,450.50 is 345_050.
      add :amount_cents, :integer, null: false
      add :category, :string, null: false
      # How it got here: "manual" when typed in.
      add :source, :string, null: false, default: "manual"

      timestamps()
    end

    create index(:transactions, [:date])
  end
end
