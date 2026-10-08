defmodule RisitiApp.Repo.Migrations.AddSync do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      # Changed here since the server last had it. Everything already on the
      # phone starts out unsent, so the first sync sends the whole book.
      add :needs_push, :boolean, null: false, default: true
      # The server has the photo, so it isn't sent again.
      add :photo_pushed, :boolean, null: false, default: false
      # The server's id for it, once it has it.
      add :remote_id, :string
      add :synced_at, :utc_datetime
    end

    alter table(:transaction_attachments) do
      add :remote_id, :string
    end

    # Transactions deleted here, until the server has been told.
    create table(:sync_deletions) do
      add :client_id, :string, null: false
      timestamps(updated_at: false)
    end

    create unique_index(:sync_deletions, [:client_id])
  end
end
