defmodule Risiti.Accounts.UserIdentity do
  @moduledoc """
  A sign-in account from elsewhere linked to a Risiti user: for now a
  Google account (`provider: "google"`, `uid` its `sub`, which never
  changes), so signing in with it finds the same person even if their
  email changes.
  """

  use Ash.Resource,
    domain: Risiti.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "user_identities"
    repo Risiti.Repo

    references do
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read, create: [:user_id, :provider, :uid]]
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :provider, :string, allow_nil?: false, public?: true
    attribute :uid, :string, allow_nil?: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :user, Risiti.Accounts.User, allow_nil?: false
  end

  identities do
    identity :unique_provider_uid, [:provider, :uid]
  end
end
