defmodule RisitiApp.Accounts.Profile do
  @moduledoc """
  Who this phone's book belongs to on the Risiti server, and what the
  server says they may do. No API token means the book isn't connected:
  everything still works, it just stays on the phone.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "profiles" do
    field :phone, :string
    field :name, :string

    field :api_token, :string, redact: true
    field :remote_user_id, :string
    field :team, :string
    field :team_kind, :string
    field :team_name, :string

    field :can_approve, :boolean, default: false
    field :can_mark_paid, :boolean, default: false
    field :can_list_all, :boolean, default: false
    field :can_export, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @server_fields [
    :phone,
    :name,
    :api_token,
    :remote_user_id,
    :team,
    :team_kind,
    :team_name,
    :can_approve,
    :can_mark_paid,
    :can_list_all,
    :can_export
  ]

  @doc "What the server said at sign-in, or later from /api/me."
  def server_changeset(profile, attrs) do
    profile
    |> cast(attrs, @server_fields)
    |> validate_required([:phone])
  end

  @spec connected?(t() | nil) :: boolean()
  def connected?(%__MODULE__{api_token: token}) when is_binary(token), do: true
  def connected?(_profile), do: false

  @doc "A connected book that's just this person's: no approvals, refunds or payment requests."
  @spec personal?(t() | nil) :: boolean()
  def personal?(%__MODULE__{team_kind: "personal"} = profile), do: connected?(profile)
  def personal?(_profile), do: false

  @doc "Someone the server lets approve, or pay out, in a business team."
  @spec manager?(t() | nil) :: boolean()
  def manager?(%__MODULE__{} = profile),
    do:
      connected?(profile) and not personal?(profile) and
        (profile.can_approve or profile.can_mark_paid)

  def manager?(_profile), do: false
end
