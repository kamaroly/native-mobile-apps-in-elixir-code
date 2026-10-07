defmodule Risiti.Accounts.UserGroup do
  @moduledoc "Someone in a team's group: a user (from `public`) in a group (in the team's schema)."

  use Ash.Resource,
    domain: Risiti.Accounts,
    data_layer: AshPostgres.DataLayer,
    fragments: [Risiti.Accounts.Fragments.Multitenancies]

  postgres do
    table "user_groups"
    repo Risiti.Repo

    references do
      reference :group, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy, create: [:user_id, :group_id]]
  end

  attributes do
    uuid_v7_primary_key :id
    timestamps()
  end

  relationships do
    belongs_to :user, Risiti.Accounts.User, allow_nil?: false
    belongs_to :group, Risiti.Accounts.Group, allow_nil?: false
  end

  identities do
    identity :unique_user_group, [:user_id, :group_id]
  end
end
