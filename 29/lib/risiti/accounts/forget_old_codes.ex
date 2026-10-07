defmodule Risiti.Accounts.ForgetOldCodes do
  @moduledoc """
  Runs every night (Oban's cron, see `config/config.exs`): deletes sign-in
  codes more than a day old. They're useless after 10 minutes, and only
  kept an hour for the rate limits.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Ash.Query

  @impl Oban.Worker
  def perform(_job) do
    yesterday = DateTime.add(DateTime.utc_now(), -1, :day)

    Risiti.Accounts.PhoneCode
    |> Ash.Query.filter(inserted_at < ^yesterday)
    |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false, strategy: [:atomic, :stream])

    :ok
  end
end
