defmodule Risiti.SMSWorker do
  @moduledoc """
  Sends a text message in the background through `Risiti.SMS.deliver/2`.

  A failed send is retried with Oban's backoff. Sign-in codes expire after
  10 minutes, so there are only a few attempts, roughly inside that time.
  """

  use Oban.Worker, queue: :sms, max_attempts: 5

  @doc "Queues `text` to be sent to `phone`."
  @spec enqueue(String.t(), String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(phone, text) do
    %{"phone" => phone, "text" => text}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"phone" => phone, "text" => text}}) do
    Risiti.SMS.deliver(phone, text)
  end
end
