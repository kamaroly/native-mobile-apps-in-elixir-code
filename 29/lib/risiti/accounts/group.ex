defmodule Risiti.Accounts.Group do
  @moduledoc """
  A user role in a team ("Approvers", "Accountants"): a name and the
  permissions it grants (see `Risiti.Accounts.Permissions`). Every team
  starts with two (`seed`), and can make more.
  """

  use Ash.Resource,
    domain: Risiti.Accounts,
    data_layer: AshPostgres.DataLayer,
    fragments: [Risiti.Accounts.Fragments.Multitenancies]

  postgres do
    table "groups"
    repo Risiti.Repo
  end

  @defaults [
    %{
      name: "Accountants",
      description: "See and export every transaction in the team",
      permissions: ["transactions:list_all_transactions", "transactions:export_transactions"]
    },
    %{
      name: "Approvers",
      description: "Approve or reject transactions, and mark refunds and payments paid",
      permissions: ["transactions:approve_transactions", "transactions:mark_transactions_paid"]
    }
  ]

  code_interface do
    define :seed
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:name, :description, :permissions],
      update: [:name, :description, :permissions]
    ]

    action :seed do
      description "Adds the default groups to a team's schema, keeping any already there"

      run fn input, context ->
        @defaults
        |> Ash.bulk_create(
          __MODULE__,
          :create,
          Ash.Context.to_opts(context) ++
            [
              tenant: input.tenant,
              upsert?: true,
              upsert_identity: :unique_name,
              upsert_fields: [],
              return_errors?: true
            ]
        )
        |> case do
          %Ash.BulkResult{status: :success} -> :ok
          %Ash.BulkResult{errors: errors} -> {:error, errors}
        end
      end
    end
  end

  validations do
    validate {Risiti.Accounts.Permissions.Known, attribute: :permissions}
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true
    attribute :permissions, {:array, :string}, allow_nil?: false, default: [], public?: true
    timestamps()
  end

  relationships do
    has_many :user_groups, Risiti.Accounts.UserGroup
  end

  identities do
    identity :unique_name, [:name]
  end
end
