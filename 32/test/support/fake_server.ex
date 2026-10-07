defmodule RisitiApp.FakeServer do
  @moduledoc """
  Stands in for the Risiti server in tests (`config :risiti_app, :http`).

  A test scripts the replies with `stub/1`: a function from
  `{method, path, request}` to `{status, body}`, or `{:error, reason}` for
  a connection that failed. Every call is also sent to the test process as
  `{:http, method, path, request}`, so a test can check what the phone sent.

  Under tests, `RisitiApp.Native.background/3` runs its work in the test
  process, so the stub can live in the process dictionary.
  """

  @key {__MODULE__, :handler}

  def stub(handler) when is_function(handler, 1), do: Process.put(@key, handler)

  def request(method, url, opts) do
    path = URI.parse(url).path
    request = %{headers: Keyword.get(opts, :headers, []), body: Keyword.get(opts, :body)}
    send(self(), {:http, method, path, request})

    handler = Process.get(@key) || fn _ -> {:error, :econnrefused} end

    case handler.({method, path, request}) do
      {:error, reason} -> {:error, reason}
      {status, body} -> {:ok, status, body}
    end
  end

  @doc "The fields of a multipart body, as a map (files as `{:file, filename}`)."
  def multipart_fields({:multipart, parts}) do
    Map.new(parts, fn
      {name, {:file, _path, filename, _type}} -> {name, {:file, filename}}
      {name, value} -> {name, value}
    end)
  end

  @doc "Every value of a repeated multipart field, such as `attachments[]`."
  def multipart_all({:multipart, parts}, field), do: for({^field, value} <- parts, do: value)
end
