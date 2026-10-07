defmodule Risiti.Expenses.Transaction.Changes.ApproveInPersonalTeam do
  @moduledoc """
  In a personal book there's nobody else to approve: what the person sends
  is approved as it's saved (and again when they change it).
  """

  use Ash.Resource.Change

  alias Risiti.Accounts.Team

  @impl true
  def change(changeset, _opts, context) do
    # On create the default (pending) isn't set yet.
    with status when status in [nil, :pending] <- Ash.Changeset.get_attribute(changeset, :status),
         {:ok, %Team{kind: :personal}} <-
           Risiti.Accounts.team_for_tenant(tenant(changeset, context)) do
      Ash.Changeset.force_change_attributes(changeset, %{
        status: :approved,
        decided_at: DateTime.utc_now() |> DateTime.truncate(:second),
        decided_by_id: context.actor && context.actor.id
      })
    else
      _decided_or_business -> changeset
    end
  end

  # The tenant may not be on the changeset yet (Risiti.Changes.SetTenant runs
  # after the action's own changes); it's the actor's current team either way.
  defp tenant(%{tenant: tenant}, _context) when is_binary(tenant), do: tenant
  defp tenant(_changeset, %{actor: %{current_team: team}}), do: team
  defp tenant(_changeset, _context), do: nil
end
