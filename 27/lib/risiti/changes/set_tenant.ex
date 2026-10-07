defmodule Risiti.Changes.SetTenant do
  @moduledoc "Writes: the actor's current team is the tenant, unless one was given."

  use Ash.Resource.Change

  @impl true
  def change(%{tenant: nil} = changeset, _opts, %{actor: %{current_team: team}})
      when is_binary(team),
      do: Ash.Changeset.set_tenant(changeset, team)

  def change(changeset, _opts, _context), do: changeset

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
