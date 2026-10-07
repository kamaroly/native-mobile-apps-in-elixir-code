defmodule Risiti.Accounts do
  @moduledoc "People, the teams they belong to, and signing in."

  use Ash.Domain, otp_app: :risiti

  resources do
    resource Risiti.Accounts.Token
    resource Risiti.Accounts.User

    resource Risiti.Accounts.Team do
      define :create_team, action: :create, args: [:name, :kind]
      define :team_for_tenant, action: :by_domain, args: [:domain], not_found_error?: false
    end

    resource Risiti.Accounts.UserTeam
  end
end
