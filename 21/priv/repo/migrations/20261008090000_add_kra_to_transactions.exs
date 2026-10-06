defmodule RisitiApp.Repo.Migrations.AddKraToTransactions do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      # The QR code's text exactly as scanned, and what it identifies.
      add :qr_content, :text
      add :seller_pin, :string
      add :branch_id, :string
      add :invoice_number, :string
      # KRA's page for this receipt, and when it last confirmed the receipt.
      add :verify_url, :text
      add :verified_at, :utc_datetime
    end

    # One receipt, one transaction: scanning the same code twice is a mistake.
    create unique_index(:transactions, [:qr_content])
  end
end
