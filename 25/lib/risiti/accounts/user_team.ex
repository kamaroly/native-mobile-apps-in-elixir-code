defmodule Risiti.Accounts.UserTeam do
  @moduledoc """
  A person's membership of a team. Owners (`owner?`) may do everything in
  the team; a team can have several.
  """

  use Ash.Resource,
    domain: Risiti.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "user_teams"
    repo Risiti.Repo
  end

  actions do
    defaults [:read, :destroy, create: [:user_id, :team_id, :owner?]]
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :owner?, :boolean do
      source :owner
      allow_nil? false
      default false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Risiti.Accounts.User, allow_nil?: false
    belongs_to :team, Risiti.Accounts.Team, allow_nil?: false
  end

  identities do
    identity :unique_user_team, [:user_id, :team_id]
  end
end
