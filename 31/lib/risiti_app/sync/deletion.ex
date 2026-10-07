defmodule RisitiApp.Sync.Deletion do
  @moduledoc """
  A transaction deleted on the phone, waiting for the next sync to tell the
  server. Until then, the pull doesn't bring it back.
  """

  use Ecto.Schema

  schema "sync_deletions" do
    field :client_id, :string
    timestamps(updated_at: false)
  end
end
