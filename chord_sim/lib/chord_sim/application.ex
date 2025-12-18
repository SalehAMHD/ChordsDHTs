defmodule ChordSim.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ChordSimWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:chord_sim, :dns_cluster_query) || :ignore},
      {Cluster.Supervisor, [Application.get_env(:libcluster, :topologies, []), [name: ChordSim.ClusterSupervisor]]},
      {Phoenix.PubSub, name: ChordSim.PubSub},
      {Horde.Registry,
       name: ChordSim.NodeRegistry,
       keys: :unique,
       members: :auto},
      {Horde.DynamicSupervisor,
       name: ChordSim.NodeSupervisor,
       strategy: :one_for_one,
       members: :auto},
      ChordSimWeb.Endpoint
    ]


    opts = [strategy: :one_for_one, name: ChordSim.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ChordSimWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
