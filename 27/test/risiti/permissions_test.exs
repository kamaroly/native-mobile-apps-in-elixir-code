defmodule Risiti.PermissionsTest do
  use Risiti.DataCase, async: false

  alias Risiti.Accounts
  alias Risiti.Accounts.{Group, Permissions, User, UserGroup, UserTeam}

  setup do
    owner = Ash.Seed.seed!(User, %{phone: "+254700000001", name: "Wanjiku"})
    team = Accounts.create_team!("Duka Ltd", :business, actor: owner)
    owner = Ash.reload!(owner, authorize?: false)

    member =
      Ash.Seed.seed!(User, %{phone: "+254700000002", name: "Otieno", current_team: team.domain})

    Ash.create!(UserTeam, %{user_id: member.id, team_id: team.id}, authorize?: false)

    %{owner: owner, member: member, team: team}
  end

  test "a new team has the two default groups", %{owner: owner} do
    names = Group |> Ash.read!(actor: owner, authorize?: false) |> Enum.map(& &1.name)
    assert Enum.sort(names) == ["Accountants", "Approvers"]
  end

  test "owners may do everything", %{owner: owner} do
    for permission <- Permissions.all(), do: assert(Permissions.can?(owner, permission))
  end

  test "others may do what their groups grant", %{owner: owner, member: member} do
    refute Permissions.can?(member, "transactions:approve_transactions")

    approvers =
      Group |> Ash.read!(actor: owner, authorize?: false) |> Enum.find(&(&1.name == "Approvers"))

    Ash.create!(UserGroup, %{user_id: member.id, group_id: approvers.id}, actor: owner)

    assert Permissions.can?(member, "transactions:approve_transactions")
    assert Permissions.can?(member, "transactions:mark_transactions_paid")
    refute Permissions.can?(member, "transactions:list_all_transactions")
  end

  test "a group can't grant a permission that doesn't exist", %{owner: owner} do
    assert {:error, %Ash.Error.Invalid{}} =
             Ash.create(Group, %{name: "Gods", permissions: ["everything:all"]}, actor: owner)
  end

  test "being an owner of one team means nothing in another", %{member: member} do
    {:ok, other} = Accounts.create_team("Otieno Motors", :business, actor: member)
    member = Ash.reload!(member, authorize?: false)
    assert member.current_team == other.domain
    assert Permissions.owner?(member)

    assert {:ok, member} =
             Ash.update(member, %{team: "t_does_not_matter"},
               action: :set_current_team,
               authorize?: false
             )

    refute Permissions.owner?(member)
  end
end
