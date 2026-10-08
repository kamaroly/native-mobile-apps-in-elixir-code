defmodule Risiti.Accounts.PushDevice do
  @moduledoc """
  A phone that gets push notifications for a user: the token Firebase
  (Android) or APNs (iOS) gave the app, which the app reports after
  signing in. See `Risiti.Push`.

  A token belongs to one phone, so registering it again (say, after
  someone else signs in on that phone) moves it to the new user.
  """

  use Ash.Resource,
    domain: Risiti.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "push_devices"
    repo Risiti.Repo

    references do
      reference :user, on_delete: :delete
    end
  end

  code_interface do
    define :register, args: [:platform, :token]
    define :of_users, args: [:user_ids]
  end

  actions do
    defaults [:read, :destroy]

    create :register do
      accept [:platform, :token]
      upsert? true
      upsert_identity :unique_token
      upsert_fields [:user_id, :platform, :updated_at]
      change relate_actor(:user)
    end

    read :of_users do
      argument :user_ids, {:array, :uuid}, allow_nil?: false
      filter expr(user_id in ^arg(:user_ids))
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :platform, :atom do
      constraints one_of: [:ios, :android]
      allow_nil? false
      public? true
    end

    attribute :token, :string, allow_nil?: false, public?: true, sensitive?: true

    timestamps()
  end

  relationships do
    belongs_to :user, Risiti.Accounts.User, allow_nil?: false
  end

  identities do
    identity :unique_token, [:token]
  end
end
