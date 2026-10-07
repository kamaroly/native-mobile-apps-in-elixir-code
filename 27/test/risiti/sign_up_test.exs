defmodule Risiti.SignUpTest do
  use Risiti.DataCase, async: false

  alias Risiti.Accounts
  alias Risiti.Accounts.{Permissions, SignUp, User}

  test "just me: a personal book" do
    token = SignUp.token(%{"phone" => "+254712345678"})

    assert {:ok, %User{} = user, api_token} = SignUp.register(token, %{"name" => "Wanjiku"})
    assert user.phone == "+254712345678"
    assert is_binary(api_token)

    {:ok, team} = Accounts.team_for_tenant(user.current_team)
    assert team.kind == :personal
    assert team.name == "Personal"
    assert Permissions.owner?(user)
  end

  test "my business: a business team they own" do
    token = SignUp.token(%{"phone" => "+254712345678"})

    {:ok, user, _} = SignUp.register(token, %{"name" => "Wanjiku", "team_name" => "Duka Ltd"})

    {:ok, team} = Accounts.team_for_tenant(user.current_team)
    assert team.kind == :business
    assert team.name == "Duka Ltd"
    assert Permissions.can?(user, "transactions:approve_transactions")
  end

  test "registering twice signs in the first time's person" do
    token = SignUp.token(%{"phone" => "+254712345678"})

    {:ok, first, _} = SignUp.register(token, %{"name" => "Wanjiku"})
    {:ok, second, _} = SignUp.register(token, %{"name" => "Wanjiku"})

    assert first.id == second.id
    assert Ash.count!(Risiti.Accounts.Team, authorize?: false) == 1
  end

  test "a name is needed, and nothing is left behind without one" do
    token = SignUp.token(%{"phone" => "+254712345678"})

    assert {:error, %Ash.Error.Invalid{}} = SignUp.register(token, %{"name" => "  "})
    assert Ash.count!(User, authorize?: false) == 0
  end

  test "a made-up token is refused" do
    assert {:error, :expired} = SignUp.register("not a token", %{"name" => "Mallory"})
  end
end
