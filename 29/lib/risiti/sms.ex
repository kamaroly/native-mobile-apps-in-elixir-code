defmodule Risiti.SMS do
  @moduledoc """
  Sends text messages through the adapter in `config :risiti, Risiti.SMS`:

    * `Risiti.SMS.Log` (the default: dev and test) logs the message instead
      of sending it, and also sends `{:sms, phone, text}` to the calling
      process, for tests;
    * `Risiti.SMS.AfricasTalking` (production) needs `:username` and
      `:api_key`, and optionally `:sender_id`.
  """

  @callback deliver(phone :: String.t(), text :: String.t(), config :: keyword()) ::
              :ok | {:error, term()}

  @spec deliver(String.t(), String.t()) :: :ok | {:error, term()}
  def deliver(phone, text) do
    config = Application.get_env(:risiti, __MODULE__, [])
    adapter = Keyword.get(config, :adapter, Risiti.SMS.Log)
    adapter.deliver(phone, text, config)
  end
end

defmodule Risiti.SMS.Log do
  @moduledoc "Logs messages instead of sending them (dev and test)."
  @behaviour Risiti.SMS
  require Logger

  @impl true
  def deliver(phone, text, _config) do
    Logger.info("SMS to #{phone}: #{text}")
    send(self(), {:sms, phone, text})
    :ok
  end
end

defmodule Risiti.SMS.AfricasTalking do
  @moduledoc "Sends SMS through Africa's Talking's messaging API."
  @behaviour Risiti.SMS

  @impl true
  def deliver(phone, text, config) do
    form =
      [username: Keyword.fetch!(config, :username), to: phone, message: text] ++
        if(sender = config[:sender_id], do: [from: sender], else: [])

    case Req.post(Keyword.get(config, :url, "https://api.africastalking.com/version1/messaging"),
           form: form,
           headers: [apikey: Keyword.fetch!(config, :api_key), accept: "application/json"]
         ) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end
end
