defmodule Risiti.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RisitiWeb.Telemetry,
      Risiti.Repo,
      {Cachex, [:risiti]},
      {DNSCluster, query: Application.get_env(:risiti, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Risiti.PubSub},
      # Start a worker by calling: Risiti.Worker.start_link(arg)
      # {Risiti.Worker, arg},
      # Start to serve requests, typically the last entry
      RisitiWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :risiti]}
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Risiti.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RisitiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
