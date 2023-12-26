defmodule Ots.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      OtsWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:ots, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Ots.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Ots.Finch},
      # Start a worker by calling: Ots.Worker.start_link(arg)
      # {Ots.Worker, arg},
      {Ots.ExpirationChecker, []},
      # Start to serve requests, typically the last entry
      OtsWeb.Endpoint
    ]

    # Make sure ETS table exists
    :ets.new(:secrets, [:set, :public, :named_table])

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ots.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    OtsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
