defmodule Risiti.TeamsTest do
  use Risiti.DataCase, async: false

  alias Risiti.Accounts
  alias Risiti.Accounts.{Team, User}
  alias Risiti.Expenses.Category

  defp user(email) do
    Ash.Seed.seed!(User, %{email: email, hashed_password: "not used", name: "Wanjiku"})
  end

  test "a new team gets its own schema, its owner and the default categories" do
    owner = user("wanjiku@example.com")

    team = Accounts.create_team!("Duka Ltd", :business, actor: owner)

    assert team.domain =~ ~r/^t_[a-z0-9]+$/
    assert team.owner_user_id == owner.id

    schemas = Repo.query!("SELECT schema_name FROM information_schema.schemata").rows
    assert [team.domain] in schemas

    [membership] = team |> Ash.load!(:memberships) |> Map.fetch!(:memberships)
    assert membership.user_id == owner.id
    assert membership.owner?

    owner = Ash.reload!(owner, authorize?: false)
    assert owner.current_team == team.domain

    names = [actor: owner] |> Category.list_categories!() |> Enum.map(& &1.name)
    assert Enum.sort(names) == Enum.sort(Category.defaults())
  end

  test "a personal book's domain starts with p_" do
    team = Accounts.create_team!("Personal", :personal, actor: user("me@example.com"))
    assert team.domain =~ ~r/^p_/
    assert team.kind == :personal
  end

  test "each team sees only its own categories" do
    wanjiku = user("wanjiku@example.com")
    otieno = user("otieno@example.com")
    Accounts.create_team!("Duka Ltd", :business, actor: wanjiku)
    Accounts.create_team!("Otieno Motors", :business, actor: otieno)
    wanjiku = Ash.reload!(wanjiku, authorize?: false)
    otieno = Ash.reload!(otieno, authorize?: false)

    Ash.create!(Category, %{name: "Spare parts"}, actor: otieno)

    otieno_sees = [actor: otieno] |> Category.list_categories!() |> Enum.map(& &1.name)
    wanjiku_sees = [actor: wanjiku] |> Category.list_categories!() |> Enum.map(& &1.name)

    assert "Spare parts" in otieno_sees
    refute "Spare parts" in wanjiku_sees
  end

  test "reading a team's resource with no team at all is refused" do
    assert {:error, %Ash.Error.Invalid{}} = Category.list_categories()
  end

  test "a team is made by someone" do
    assert {:error, _} = Accounts.create_team("Nobody's", :business)
  end

  test "the domain is a safe schema name" do
    owner = user("wanjiku@example.com")

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.create(Team, %{name: "Bad", domain: "drop table"}, actor: owner)
  end
end
