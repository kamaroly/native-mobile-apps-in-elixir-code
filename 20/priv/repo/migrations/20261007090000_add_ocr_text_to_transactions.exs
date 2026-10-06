defmodule RisitiApp.Repo.Migrations.AddOcrTextToTransactions do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      # Everything the phone read off the receipt photo, kept for search.
      add :ocr_text, :text
    end
  end
end
