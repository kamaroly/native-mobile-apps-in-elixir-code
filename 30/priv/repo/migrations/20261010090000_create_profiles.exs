defmodule RisitiApp.Repo.Migrations.CreateProfiles do
  use Ecto.Migration

  # Who this phone's book belongs to on the server. There's at most one row:
  # it's made the first time someone signs in.
  def change do
    create table(:profiles) do
      add :phone, :string, null: false
      add :name, :string

      # From the server: the API token, who they are there, and their team.
      add :api_token, :string
      add :remote_user_id, :string
      add :team, :string
      add :team_kind, :string
      add :team_name, :string

      # What the server says they may do in that team (GET /api/me).
      add :can_approve, :boolean, null: false, default: false
      add :can_mark_paid, :boolean, null: false, default: false
      add :can_list_all, :boolean, null: false, default: false
      add :can_export, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end
  end
end
