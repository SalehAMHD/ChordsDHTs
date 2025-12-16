defmodule ChordSim.Node do
  use GenServer

  @m 32

  ## Public API
  def start_link(opts) when is_list(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, id, name: via(id))
  end

  def via(id), do: {:via, Registry, {ChordSim.NodeRegistry, id}}

  def join(id, known_id \\ nil), do: GenServer.call(via(id), {:join, known_id})
  def find_successor(id, key), do: GenServer.call(via(id), {:find_successor, key})
  def put(id, key, value), do: GenServer.call(via(id), {:put, key, value})
  def get(id, key), do: GenServer.call(via(id), {:get, key})
  def info(id), do: GenServer.call(via(id), :info)

  ## Callbacks
  @impl true
  def init(id) do
    table = :ets.new(String.to_atom("node_#{id}_table"), [:set, :protected, :named_table])

    state = %{
      id: id,
      m: @m,
      predecessor: nil,
      successor: id,
      table: table
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:join, nil}, _from, state) do
    # Premier noeud : boucle sur lui-même
    {:reply, :ok, %{state | successor: state.id, predecessor: state.id}}
  end

  def handle_call({:join, known_id}, _from, state) do
    {:ok, succ} = GenServer.call(via(known_id), {:find_successor, state.id})
    {:reply, :ok, %{state | successor: succ}}
  end

  def handle_call({:find_successor, key}, _from, state) do
    cond do
      state.successor == state.id ->
        {:reply, {:ok, state.id}, state}

      in_interval?(key, state.id, state.successor) ->
        {:reply, {:ok, state.successor}, state}

      true ->
        GenServer.call(via(state.successor), {:find_successor, key})
    end
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
    {:reply, %{id: state.id, succ: state.successor, pred: state.predecessor}, state}
  end

  @impl true
  def terminate(_reason, state) do
    if is_atom(state.table), do: :ets.delete(state.table)
    :ok
  end

  defp in_interval?(key, start_id, end_id) do
    cond do
      start_id < end_id -> key > start_id and key <= end_id
      start_id > end_id -> key > start_id or key <= end_id
      true -> true
    end
  end
end
