defmodule ChordSim.NodeSupervisor do
  @moduledoc """
  Helper wrapper around `DynamicSupervisor` to start/stop Chord nodes.
  """

  def start_node(id) do
    Horde.DynamicSupervisor.start_child(ChordSim.NodeSupervisor, {ChordSim.Node, id: id})
  end

  def stop_node(id) do
    case Horde.Registry.lookup(ChordSim.NodeRegistry, id) do
      [{pid, _}] -> Horde.DynamicSupervisor.terminate_child(ChordSim.NodeSupervisor, pid)
      [] -> {:error, :not_found}
    end
  end
end
