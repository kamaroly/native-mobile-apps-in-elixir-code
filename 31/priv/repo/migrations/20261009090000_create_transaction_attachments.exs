defmodule RisitiApp.Repo.Migrations.CreateTransactionAttachments do
  use Ecto.Migration

  def change do
    create table(:transaction_attachments) do
      add :transaction_id, references(:transactions, on_delete: :delete_all), null: false
      # Stored file name in the app's attachments folder.
      add :file_name, :string, null: false
      # The name the person knows it by: "Invoice 2041.pdf".
      add :name, :string, null: false
      add :content_type, :string, null: false
      add :size, :integer, null: false

      timestamps()
    end

    create index(:transaction_attachments, [:transaction_id])
  end
end
