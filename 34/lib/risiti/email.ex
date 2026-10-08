defmodule Risiti.Email do
  @moduledoc """
  Emails people about what needs their attention, alongside the push
  (`Risiti.Push`): the same title and message, for those who have an
  email address. Each email is a job on the `mailers` queue
  (`Risiti.MailerWorker`), so a slow mail server never holds anything up.
  """

  require Ash.Query

  alias Risiti.Accounts.User

  @doc """
  Queues an email to each of `user_ids` who has an address: `title` as the
  subject, then `body`, then a link to `path` on the web. Returns how many
  were queued.
  """
  @spec notify([Ecto.UUID.t()], String.t(), String.t(), String.t()) :: non_neg_integer()
  def notify([], _title, _body, _path), do: 0

  def notify(user_ids, title, body, path) do
    text = "#{body}\n\n#{RisitiWeb.Endpoint.url()}#{path}\n\n-- \nRisiti\n"

    User
    |> Ash.Query.filter(id in ^user_ids and not is_nil(email))
    |> Ash.read!(authorize?: false)
    |> Enum.map(
      &Risiti.MailerWorker.new(%{"to" => to_string(&1.email), "subject" => title, "text" => text})
    )
    |> Oban.insert_all()
    |> length()
  end
end
