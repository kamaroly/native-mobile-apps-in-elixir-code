defmodule RisitiApp.Sync do
  @moduledoc """
  Keeps a connected book and the Risiti server in step.

  One run:

    1. **deletes** on the server what was deleted here. The server keeps
       anything already decided, and step 3 brings it back;
    2. **pushes** transactions changed since the server last had them
       (`needs_push`), with the photo until the server has it and the
       attachments it hasn't got yet;
    3. **pulls** the decisions back (status, note, when paid), and adds what
       the server has that the phone doesn't, after a reinstall say. Their
       photos and attachments download the first time they're opened;
    4. refreshes what the person may do (`/api/me`).

  Everything is keyed by `client_id`, so a run cut short by a dropped
  connection is simply run again. A transaction is marked sent only if it
  wasn't edited while it was on its way, so an edit is never lost.

  The phone owns the figures; the server owns the decisions.
  """

  import Ecto.Query, only: [from: 2]

  alias RisitiApp.{Accounts, Api, Repo}
  alias RisitiApp.Accounts.Profile
  alias RisitiApp.Receipts.Photos
  alias RisitiApp.Sync.Deletion
  alias RisitiApp.Transactions.{Attachment, Attachments, Transaction}

  @type summary :: %{
          pushed: non_neg_integer(),
          failed: non_neg_integer(),
          pulled: non_neg_integer()
        }

  @doc """
  Runs a sync in a process of its own, and sends `{:sync, result}` to
  `notify` when it's done. If a run is already going, this one doesn't
  start: the one going will do.
  """
  @spec start(pid() | nil) :: :ok
  def start(notify \\ nil) do
    Task.start(fn ->
      # Taking the name is the lock: only one process can have it.
      if register() do
        result = run()
        if notify, do: send(notify, {:sync, result})
      end
    end)

    :ok
  end

  defp register do
    Process.register(self(), __MODULE__)
    true
  rescue
    ArgumentError -> false
  end

  @doc "Syncs the book, if it's connected."
  @spec run() :: {:ok, summary()} | {:error, :not_connected | :offline | :unauthorized}
  def run do
    profile = Accounts.current_profile()
    if Profile.connected?(profile), do: run(profile), else: {:error, :not_connected}
  end

  @spec run(Profile.t()) :: {:ok, summary()} | {:error, :offline | :unauthorized}
  def run(%Profile{} = profile) do
    with :ok <- push_deletions(profile),
         {:ok, pushed} <- push_transactions(profile),
         {:ok, pulled} <- pull(profile) do
      refresh_permissions(profile)
      {:ok, Map.put(pushed, :pulled, pulled)}
    end
  end

  # ── Deletions ──────────────────────────────────────────────────────────────

  @doc "Notes that a transaction was deleted here, for the next sync to tell the server."
  @spec remember_deletion(String.t()) :: :ok
  def remember_deletion(client_id) do
    Repo.insert!(%Deletion{client_id: client_id}, on_conflict: :nothing)
    :ok
  end

  defp push_deletions(profile) do
    Repo.all(from d in Deletion, order_by: d.id)
    |> Enum.reduce_while(:ok, fn deletion, :ok ->
      case Api.delete_transaction(profile, deletion.client_id) do
        # Can't reach the server, or not allowed: stop, and try next time.
        {:error, reason} when reason in [:offline, :unauthorized] ->
          {:halt, {:error, reason}}

        # Gone, or kept because it was decided: either way the server has the
        # last word, and the pull brings back whatever it kept.
        {:ok, _} ->
          forget(deletion)

        {:error, {:invalid, _}} ->
          forget(deletion)

        # Anything else: try again next time.
        _other ->
          {:cont, :ok}
      end
    end)
  end

  defp forget(deletion) do
    Repo.delete!(deletion)
    {:cont, :ok}
  end

  # ── Push ───────────────────────────────────────────────────────────────────

  # Stops at the first sign the server can't be used (offline, signed out);
  # a transaction the server refuses is counted and skipped.
  defp push_transactions(profile) do
    from(t in Transaction, where: t.needs_push, order_by: t.id, preload: :attachments)
    |> Repo.all()
    |> Enum.reduce_while({:ok, %{pushed: 0, failed: 0}}, fn transaction, {:ok, acc} ->
      case push(profile, transaction) do
        :ok -> {:cont, {:ok, %{acc | pushed: acc.pushed + 1}}}
        {:error, reason} when reason in [:offline, :unauthorized] -> {:halt, {:error, reason}}
        {:error, _refused} -> {:cont, {:ok, %{acc | failed: acc.failed + 1}}}
      end
    end)
  end

  defp push(profile, transaction) do
    with {:ok, %{"transaction" => json}} <- Api.put_transaction(profile, transaction) do
      mark_pushed(transaction, json)
    end
  end

  # Only if nobody edited it while it was on its way: an edit made during
  # the upload keeps `needs_push`, and goes up next time. The attachments
  # the server now has get their ids either way, so they aren't sent again.
  defp mark_pushed(transaction, json) do
    from(t in Transaction,
      where: t.id == ^transaction.id and t.updated_at == ^transaction.updated_at
    )
    |> Repo.update_all(
      set:
        [
          needs_push: false,
          photo_pushed: transaction.photo_path != nil,
          remote_id: json["id"],
          synced_at: now()
        ] ++ decision(json)
    )

    remote = Map.new(json["attachments"] || [], &{{&1["name"], &1["size"]}, &1["id"]})

    for attachment <- transaction.attachments,
        is_nil(attachment.remote_id),
        id = remote[{attachment.name, attachment.size}] do
      attachment |> Ecto.Changeset.change(remote_id: id) |> Repo.update!()
    end

    :ok
  end

  # ── Pull ───────────────────────────────────────────────────────────────────

  defp pull(profile) do
    with {:ok, %{"transactions" => jsons}} <- Api.list_transactions(profile) do
      known = %{
        local: Repo.all(from t in Transaction, select: t.client_id) |> MapSet.new(),
        deleted: Repo.all(from d in Deletion, select: d.client_id) |> MapSet.new()
      }

      {:ok, Enum.reduce(jsons, 0, &(&2 + pull_one(&1, known)))}
    end
  end

  # How many transactions on the phone this changed: 0 or 1.
  defp pull_one(%{"client_id" => client_id} = json, known) do
    cond do
      # Ours: take the decision, unless it has changes the server hasn't
      # seen yet. Those go up first, and the server decides again.
      MapSet.member?(known.local, client_id) ->
        {updated, _} =
          from(t in Transaction, where: t.client_id == ^client_id and not t.needs_push)
          |> Repo.update_all(set: [remote_id: json["id"], synced_at: now()] ++ decision(json))

        updated

      # Deleted here, and the server hasn't been told yet.
      MapSet.member?(known.deleted, client_id) ->
        0

      # The server has it and the phone doesn't.
      true ->
        insert(json)
        1
    end
  end

  # The photo stays on the server until it's opened: `photo_path` names the
  # file it will download to, and `photo_pushed` keeps it from going back
  # up. Attachments are the same.
  defp insert(json) do
    has_photo? = json["has_photo"] == true

    Repo.transaction(fn ->
      transaction =
        Repo.insert!(%Transaction{
          client_id: json["client_id"],
          remote_id: json["id"],
          type: json["type"] || "expense",
          pay_to: json["pay_to"],
          date: Date.from_iso8601!(json["date"]),
          vendor: json["vendor"],
          description: json["description"],
          amount_cents: json["amount_cents"],
          category: json["category"],
          method: json["method"],
          phone: json["phone"],
          till_number: json["till_number"],
          paybill_number: json["paybill_number"],
          account_number: json["account_number"],
          source: json["source"] || "manual",
          seller_pin: json["seller_pin"],
          invoice_number: json["invoice_number"],
          verify_url: json["verify_url"],
          verified_at: parse_time(json["verified_at"]),
          photo_path: if(has_photo?, do: "remote-#{json["id"]}.jpg"),
          photo_pushed: has_photo?,
          needs_push: false,
          synced_at: now(),
          status: json["status"] || "pending",
          decision_note: json["decision_note"],
          decided_at: parse_time(json["decided_at"]),
          paid_at: parse_time(json["paid_at"])
        })

      for attachment <- json["attachments"] || [] do
        Repo.insert!(%Attachment{
          transaction_id: transaction.id,
          remote_id: attachment["id"],
          file_name: "remote-#{attachment["id"]}#{Path.extname(attachment["name"] || "")}",
          name: attachment["name"],
          content_type: attachment["content_type"],
          size: attachment["size"]
        })
      end
    end)
  end

  # ── Files kept on the server ───────────────────────────────────────────────

  @doc "Downloads a pulled transaction's photo to its `photo_path`, unless it's already here."
  @spec fetch_photo(Profile.t(), Transaction.t()) :: :ok | {:error, term()}
  def fetch_photo(profile, %Transaction{remote_id: id, photo_path: name}) when is_binary(name) do
    cond do
      Photos.exists?(name) -> :ok
      is_binary(id) -> Api.download(profile, "/api/transactions/#{id}/photo", Photos.path(name))
      true -> {:error, :no_photo}
    end
  end

  def fetch_photo(_profile, _transaction), do: {:error, :no_photo}

  @doc "Downloads a pulled attachment to its `file_name`, unless it's already here."
  @spec fetch_attachment(Profile.t(), Attachment.t()) :: :ok | {:error, term()}
  def fetch_attachment(profile, %Attachment{remote_id: id, file_name: name}) do
    cond do
      File.regular?(Attachments.path(name)) -> :ok
      is_binary(id) -> Api.download(profile, "/api/attachments/#{id}", Attachments.path(name))
      true -> {:error, :missing}
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  # What the server decided: the half of the transaction it owns.
  defp decision(json) do
    [
      status: json["status"] || "pending",
      decision_note: json["decision_note"],
      decided_at: parse_time(json["decided_at"]),
      paid_at: parse_time(json["paid_at"])
    ]
  end

  defp refresh_permissions(profile) do
    with {:ok, %{"user" => user}} <- Api.me(profile) do
      Accounts.apply_server_user(profile, user)
    end
  end

  defp parse_time(nil), do: nil

  defp parse_time(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} -> DateTime.truncate(at, :second)
      _ -> nil
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
