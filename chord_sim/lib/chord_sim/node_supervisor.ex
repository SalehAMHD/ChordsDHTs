defmodule ChordSim.NodeSupervisor do
  @moduledoc """
  Helper wrapper around `DynamicSupervisor` to start/stop Chord nodes.
  """

  def start_node(id) do
    DynamicSupervisor.start_child(ChordSim.NodeSupervisor, {ChordSim.Node, id: id})
  end

  def stop_node(id) do
    case Registry.lookup(ChordSim.NodeRegistry, id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(ChordSim.NodeSupervisor, pid)
      [] -> {:error, :not_found}
    end
  end
end
