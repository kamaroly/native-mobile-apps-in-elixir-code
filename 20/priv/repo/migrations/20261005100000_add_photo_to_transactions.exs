defmodule RisitiApp.Repo.Migrations.AddPhotoToTransactions do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      # A file name in receipt_photos/, never a full path.
      add :photo_path, :string
    end
  end
end
