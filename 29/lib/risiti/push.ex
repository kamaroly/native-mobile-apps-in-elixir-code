defmodule Risiti.Push do
  @moduledoc """
  Push notifications to the phone, through the adapter in
  `config :risiti, Risiti.Push`:

    * `Risiti.Push.Log` (the default: dev and test) logs the notification
      instead of sending it, and also sends `{:push, token, platform,
      payload}` to the calling process, for tests;
    * `MobPush` (production) sends it through Firebase (Android) or APNs
      (iOS), with the credentials in `config :mob_push`.

  Phones tell the server their tokens through the API
  (`Risiti.Accounts.PushDevice`). A token Firebase says is gone is
  forgotten.
  """

  require Logger

  alias Risiti.Accounts.PushDevice

  @type payload :: %{title: String.t(), body: String.t(), data: map()}

  @callback send(token :: String.t(), platform :: :ios | :android, payload()) ::
              :ok | {:error, term()}

  @doc "Sends `payload` to every phone of each user in `user_ids`."
  @spec notify([Ecto.UUID.t()], payload()) :: :ok
  def notify([], _payload), do: :ok

  def notify(user_ids, payload) do
    user_ids
    |> PushDevice.of_users!(authorize?: false)
    |> Enum.each(&deliver(&1, payload))
  end

  defp deliver(%PushDevice{token: token, platform: platform} = device, payload) do
    case adapter().send(token, platform, payload) do
      :ok ->
        :ok

      {:error, reason} when reason in [:device_token_not_found, :device_token_expired] ->
        Ash.destroy!(device, authorize?: false)

      {:error, reason} ->
        Logger.warning("Push to #{platform} device failed: #{inspect(reason)}")
    end
  end

  defp adapter do
    :risiti |> Application.get_env(__MODULE__, []) |> Keyword.get(:adapter, Risiti.Push.Log)
  end
end

defmodule Risiti.Push.Log do
  @moduledoc "Logs push notifications instead of sending them (dev and test)."
  @behaviour Risiti.Push
  require Logger

  @impl true
  def send(token, platform, payload) do
    Logger.info(
      "Push to #{platform} #{String.slice(token, 0, 8)}…: #{payload.title} — #{payload.body}"
    )

    Kernel.send(self(), {:push, token, platform, payload})
    :ok
  end
end
