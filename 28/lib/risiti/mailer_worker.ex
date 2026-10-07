defmodule Risiti.MailerWorker do
  @moduledoc """
  Sends one email in the background. Args: `to`, `subject` and `text`. It
  comes from `config :risiti, :mail_from`.
  """

  use Oban.Worker, queue: :mailers, max_attempts: 5

  import Swoosh.Email

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"to" => to, "subject" => subject, "text" => text}}) do
    new()
    |> from(Application.get_env(:risiti, :mail_from, {"Risiti", "no-reply@example.com"}))
    |> to(to)
    |> subject(subject)
    |> text_body(text)
    |> Risiti.Mailer.deliver()
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
