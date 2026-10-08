defmodule Risiti.Fixtures do
  @moduledoc "People and teams for tests."

  alias Risiti.Accounts
  alias Risiti.Accounts.{Group, User, UserGroup, UserTeam}

  @doc "A user with a phone number, in no team yet."
  def user(attrs \\ %{}) do
    n = Enum.random(10_000_000..99_999_999)

    attrs =
      Map.merge(
        %{phone: "+2547" <> String.pad_leading("#{n}", 8, "0"), name: "Person #{n}"},
        Map.new(attrs)
      )

    Ash.Seed.seed!(User, attrs)
  end

  @doc """
  A business team owned by Wanjiku, with Otieno (no role), Achieng (an
  approver) and Kamau (an accountant) in it.
  """
  def business_team do
    wanjiku = user(name: "Wanjiku")
    team = Accounts.create_team!("Duka Ltd", :business, actor: wanjiku)
    wanjiku = Ash.reload!(wanjiku, authorize?: false)

    otieno = member(team, wanjiku, "Otieno", nil)
    achieng = member(team, wanjiku, "Achieng", "Approvers")
    kamau = member(team, wanjiku, "Kamau", "Accountants")

    %{team: team, owner: wanjiku, member: otieno, approver: achieng, accountant: kamau}
  end

  @doc "Someone's own personal book."
  def personal_book(name \\ "Njeri") do
    person = user(name: name)
    team = Accounts.create_team!("Personal", :personal, actor: person)
    %{team: team, owner: Ash.reload!(person, authorize?: false)}
  end

  @doc "Adds someone to `team`, in the group called `group_name` (or none)."
  def member(team, owner, name, group_name) do
    person = user(name: name, current_team: team.domain)
    Ash.create!(UserTeam, %{user_id: person.id, team_id: team.id}, authorize?: false)

    if group_name do
      group = Group |> Ash.read!(actor: owner) |> Enum.find(&(&1.name == group_name))
      Ash.create!(UserGroup, %{user_id: person.id, group_id: group.id}, actor: owner)
    end

    person
  end

  @doc "What a phone sends for a transaction: string keys, like the API's params."
  def phone_transaction(attrs \\ %{}) do
    Map.merge(
      %{
        "client_id" => Ecto.UUID.generate(),
        "type" => "expense",
        "date" => "2026-10-03",
        "vendor" => "Naivas Supermarket",
        "amount_cents" => 345_050,
        "category" => "Food & Groceries"
      },
      Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
    )
  end
end
