defmodule Risiti.Expenses.Category do
  @moduledoc """
  What a team files its spending under. Every team starts with the phone's
  categories (`seed`); transactions store the name, so the phone and the
  server agree without sharing ids.
  """

  use Ash.Resource,
    domain: Risiti.Expenses,
    data_layer: AshPostgres.DataLayer,
    fragments: [Risiti.Accounts.Fragments.Multitenancies]

  postgres do
    table "expense_categories"
    repo Risiti.Repo
  end

  @defaults [
    "Food & Groceries",
    "Meals & Entertainment",
    "Transport",
    "Fuel",
    "Utilities",
    "Airtime & Internet",
    "Rent",
    "Health",
    "Office Supplies",
    "Other"
  ]

  code_interface do
    define :list_categories, action: :read
    define :seed
  end

  actions do
    defaults [:read, :destroy, create: [:name], update: [:name]]

    action :seed do
      description "Adds the default categories to a team's schema, keeping any already there"

      run fn input, context ->
        @defaults
        |> Enum.map(&%{name: &1})
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

  attributes do
    uuid_v7_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    timestamps()
  end

  identities do
    identity :unique_name, [:name]
  end

  @doc "The categories every team starts with: the phone's."
  def defaults, do: @defaults
end
