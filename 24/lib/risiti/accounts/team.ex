defmodule Risiti.Accounts.Team do
  @moduledoc """
  A team: a business with people in it, or one person's own book. Each
  team's data lives in its own Postgres schema, named after its `domain`.
  """

  use Ash.Resource,
    domain: Risiti.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "teams"
    repo Risiti.Repo

    # Creating a team creates its schema and runs the tenant migrations in it.
    manage_tenant do
      template ["", :domain]
      create? true
      update? false
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:name, :domain, :kind]

      # A random domain unless one is given: "p_…" for a personal book,
      # "t_…" for a business.
      change fn changeset, _context ->
        if Ash.Changeset.get_attribute(changeset, :domain) do
          changeset
        else
          prefix = if Ash.Changeset.get_attribute(changeset, :kind) == :personal, do: "p", else: "t"
          Ash.Changeset.force_change_attribute(changeset, :domain, new_domain(prefix))
        end
      end

      change Risiti.Accounts.Team.Changes.SetUp
    end

    read :by_domain do
      get? true
      argument :domain, :string, allow_nil?: false
      filter expr(domain == ^arg(:domain))
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true

    attribute :domain, :string do
      description "Also the name of the team's Postgres schema"
      allow_nil? false
      public? true
      constraints match: ~r/^[a-z][a-z0-9_]{2,62}$/
    end

    attribute :kind, :atom do
      description "personal: one person's own book; business: a team that approves"
      constraints one_of: [:personal, :business]
      allow_nil? false
      default :business
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :owner, Risiti.Accounts.User, source_attribute: :owner_user_id

    has_many :memberships, Risiti.Accounts.UserTeam

    many_to_many :users, Risiti.Accounts.User do
      through Risiti.Accounts.UserTeam
      source_attribute_on_join_resource :team_id
      destination_attribute_on_join_resource :user_id
    end
  end

  identities do
    identity :unique_domain, [:domain]
  end

  # A team record used as a tenant (`tenant: team`) means its schema.
  defimpl Ash.ToTenant do
    def to_tenant(%{domain: domain}, _resource), do: domain
  end

  @doc """
  A new, unused domain: lowercase letters, digits and underscores, since
  it's also a schema name.
  """
  @spec new_domain(String.t()) :: String.t()
  def new_domain(prefix \\ "t") do
    suffix = :crypto.strong_rand_bytes(8) |> Base.encode32(case: :lower, padding: false)
    "#{prefix}_#{suffix}"
  end
end
