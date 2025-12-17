defmodule ChordSim.Node do
  use GenServer

  ## Public API
  def start_link(opts) when is_list(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, id, name: via(id))
  end

  def via(id), do: {:via, Registry, {ChordSim.NodeRegistry, id}}

  def join(id, known_id \\ nil), do: GenServer.call(via(id), {:join, known_id})
  def find_successor(id, key), do: GenServer.call(via(id), {:find_successor, key})
  def notify(id, candidate_id), do: GenServer.call(via(id), {:notify, candidate_id})

  ## Callbacks
  @impl true
  def init(id) do
    state = %{id: id, successor: id, predecessor: nil}
    {:ok, state}
  end

  @impl true
  def handle_call({:join, nil}, _from, state) do
    {:reply, :ok, %{state | successor: state.id, predecessor: state.id}}
  end

  def handle_call({:join, known_id}, _from, state) do
    {:ok, succ} = GenServer.call(via(known_id), {:find_successor, state.id})
    GenServer.call(via(succ), {:notify, state.id})
    {:reply, :ok, %{state | successor: succ, predecessor: nil}}
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

  def handle_call({:notify, candidate_id}, _from, state) do
    new_state =
      cond do
        state.predecessor == nil ->
          %{state | predecessor: candidate_id}

        in_interval?(candidate_id, state.predecessor, state.id) ->
          %{state | predecessor: candidate_id}

        true ->
          state
      end

    {:reply, :ok, new_state}
  end

  defp in_interval?(key, start_id, end_id) do
    cond do
      start_id < end_id -> key > start_id and key <= end_id
      start_id > end_id -> key > start_id or key <= end_id
      true -> true
    end
  end
end
