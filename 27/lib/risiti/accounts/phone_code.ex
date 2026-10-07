defmodule Risiti.Accounts.PhoneCode do
  @moduledoc """
  A one-time sign-in code sent by SMS. Only a keyed hash of the code is
  kept. A code expires after 10 minutes, is used once, and allows 5 wrong
  guesses. See `Risiti.Accounts.PhoneSignIn`.
  """

  use Ash.Resource,
    domain: Risiti.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "phone_codes"
    repo Risiti.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :issue do
      accept [:phone, :code_hash, :expires_at, :ip]
    end

    update :record_attempt do
      change atomic_update(:attempts, expr(attempts + 1))
    end

    update :use do
      change set_attribute(:used_at, &DateTime.utc_now/0)
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :phone, :string, allow_nil?: false
    attribute :code_hash, :string, allow_nil?: false, sensitive?: true
    attribute :expires_at, :utc_datetime, allow_nil?: false
    attribute :attempts, :integer, allow_nil?: false, default: 0
    attribute :used_at, :utc_datetime

    attribute :ip, :string do
      description "Who asked, to limit how many codes one address can have sent"
    end

    create_timestamp :inserted_at
  end
end
