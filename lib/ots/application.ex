defmodule Ots.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    topologies = [
      ots: [
        strategy: Cluster.Strategy.Gossip
      ]
    ]

    possible_children = [
      {!is_release(), {Cluster.Supervisor, [topologies, [name: Chat.ClusterSupervisor]]}},
      {true, OtsWeb.Telemetry},
      {true, {DNSCluster, query: Application.get_env(:ots, :dns_cluster_query) || :ignore}},
      {true, {Phoenix.PubSub, name: Ots.PubSub, adapter: Phoenix.PubSub.PG2}},
      # Start the Finch HTTP client for sending emails
      {true, {Finch, name: Ots.Finch}},
      # Start a worker by calling: Ots.Worker.start_link(arg)
      # {Ots.Worker, arg},
      {false, Ots.ExpirationChecker},
      # Start to serve requests, typically the last entry
      {true, OtsWeb.Endpoint}
    ]
    children = for {true, child} <- possible_children, do: child

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ots.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp is_release() do
    is_binary(System.get_env("RELEASE_NAME"))
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    OtsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
