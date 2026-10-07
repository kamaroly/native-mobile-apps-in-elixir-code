defmodule Risiti.Expenses.PushNotifier do
  @moduledoc """
  Queues a `Risiti.PushWorker` job when a transaction changes in a way
  someone else should hear about, whether it came from a phone or the web.
  Ash sends notifications after the database transaction commits, so a
  push never announces a change that was rolled back.
  """

  use Ash.Notifier

  alias Ash.Notifier.Notification
  alias Risiti.PushWorker

  @impl true
  def notify(%Notification{action: %{name: action}} = n) do
    case event(action, n) do
      nil ->
        :ok

      {event, version} ->
        PushWorker.enqueue(event, n.data, n.changeset.tenant, actor_id(n), version)
    end

    :ok
  end

  defp event(:submit, %{data: t}) when t.status == :pending, do: {"transaction_submitted", nil}

  # A changed figure sent a decided transaction back for approval.
  defp event(:update_from_phone, %{changeset: changeset, data: t}) do
    if changeset.data.status != :pending and t.status == :pending,
      do: {"transaction_resubmitted", t.updated_at}
  end

  defp event(action, %{data: t}) when action in [:approve, :reject],
    do: {"transaction_#{t.status}", t.decided_at}

  defp event(:mark_paid, %{data: t}), do: {"transaction_paid", t.paid_at}
  defp event(_action, _n), do: nil

  defp actor_id(%Notification{actor: %{id: id}}), do: id
  defp actor_id(_notification), do: nil
end
