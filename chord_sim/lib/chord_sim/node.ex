defmodule ChordSim.Node do
  @moduledoc """
  Minimal GenServer skeleton for a Chord node. Implements basic API stubs
  to be extended: join, find_successor, put/get, stabilize, fix_fingers, etc.
  """

  use GenServer

  @default_m 32

  ## Public API
  def start_link(opts) when is_list(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, %{id: id, opts: opts}, name: via_tuple(id))
  end

  def child_spec(opts) do
    id = Keyword.fetch!(opts, :id)
    %{
      id: {:chord_node, id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  defp via_tuple(id), do: {:via, Registry, {ChordSim.NodeRegistry, id}}

  # API helpers that call the GenServer by Registry name
  def join(id, known_node \\ nil), do: GenServer.call(via_tuple(id), {:join, known_node})
  def leave(id), do: GenServer.cast(via_tuple(id), :leave)
  def find_successor(id, key_id), do: GenServer.call(via_tuple(id), {:find_successor, key_id})
  def put(id, key, value), do: GenServer.call(via_tuple(id), {:put, key, value})
  def get(id, key), do: GenServer.call(via_tuple(id), {:get, key})
  def info(id), do: GenServer.call(via_tuple(id), :info)

  ## GenServer callbacks
  def init(%{id: id} = _init_arg) do
    table_name = String.to_atom("node_#{id}_table")
    # ensure unique named table per node
    if :ets.whereis(table_name) != :undefined do
      :ets.delete(table_name)
    end

    :ets.new(table_name, [:set, :protected, :named_table])

    state = %{
      id: id,
      m: @default_m,
      successor: nil,
      predecessor: nil,
      fingers: [],
      table: table_name
    }

    {:ok, state}
  end

  def handle_call({:join, _known_node}, _from, state) do
    # stub: implement join logic
    {:reply, :ok, state}
  end

  def handle_call({:find_successor, _key_id}, _from, state) do
    # stub: real implementation should route in the ring
    {:reply, {:ok, state.successor || :not_found}, state}
  end

  def handle_call({:put, key, value}, _from, state) do
    :ets.insert(state.table, {key, value})
    {:reply, :ok, state}
  end

  def handle_call({:get, key}, _from, state) do
    case :ets.lookup(state.table, key) do
      [{^key, value}] -> {:reply, {:ok, value}, state}
      [] -> {:reply, :not_found, state}
    end
  end

  def handle_call(:info, _from, state) do
    keys = :ets.tab2list(state.table)
    {:reply, %{id: state.id, successor: state.successor, predecessor: state.predecessor, keys: keys}, state}
  end

  def handle_cast(:leave, state) do
    {:stop, :normal, state}
  end

  def terminate(_reason, state) do
    if is_atom(state.table), do: :ets.delete(state.table)
    :ok
  end
end
