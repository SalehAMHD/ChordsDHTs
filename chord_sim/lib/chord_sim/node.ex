defmodule ChordSim.Node do
  use GenServer
  import Bitwise

  @m 8
  @stabilize_ms 1_000
  @check_pred_ms 2_000
  @fix_fingers_ms 1_500

  # Start a node process with a fixed integer id.
  def start_link(opts) when is_list(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, id, name: via(id))
  end

  # Name a node by id via the Registry.
  def via(id), do: {:via, Registry, {ChordSim.NodeRegistry, id}}

  # Child spec with a unique id per node (for DynamicSupervisor).
  def child_spec(opts) do
    id = Keyword.fetch!(opts, :id)

    %{
      id: {:chord_node, id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      type: :worker
    }
  end

  # Return the number of bits in the identifier space.
  def m, do: @m

  # Return the ring size (2^m).
  def ring_size, do: 1 <<< @m

  # Hash a user key into the identifier space.
  def hash_id(key), do: hash_key(key)

  # Join the ring; known_id is nil for the first node.
  def join(id, known_id \\ nil), do: GenServer.call(via(id), {:join, known_id})

  # Find the successor responsible for a key id.
  def find_successor(id, key_id), do: GenServer.call(via(id), {:find_successor, key_id})

  # Tell a node that we might be its predecessor.
  def notify(id, candidate_id), do: GenServer.call(via(id), {:notify, candidate_id})

  # Read the predecessor of a node.
  def get_predecessor(id), do: GenServer.call(via(id), :get_predecessor)

  # Read basic info for UI/debug.
  def info(id), do: GenServer.call(via(id), :info)

  # Trigger periodic stabilization manually.
  def stabilize(id), do: GenServer.cast(via(id), :stabilize)

  # Trigger predecessor check manually.
  def check_predecessor(id), do: GenServer.cast(via(id), :check_predecessor)

  # Trigger finger updates manually.
  def fix_fingers(id), do: GenServer.cast(via(id), :fix_fingers)

  # Store a key/value pair in the DHT (routed).
  def put(id, key, value), do: GenServer.call(via(id), {:put, key, value})

  # Fetch a value from the DHT (routed).
  def get(id, key), do: GenServer.call(via(id), {:get, key})

  # Show all local keys on a node (debug).
  def dump_keys(id), do: GenServer.call(via(id), :dump_keys)

  # Leave the ring gracefully.
  def leave(id), do: GenServer.call(via(id), :leave)

  @impl true
  # Initialize node state and schedule periodic tasks.
  def init(id) do
    table = :ets.new(String.to_atom("node_#{id}_table"), [:set, :protected, :named_table])

    state = %{
      id: id,
      successor: id,
      predecessor: nil,
      fingers: init_fingers(id),
      next_finger: 1,
      table: table
    }

    Process.send_after(self(), :stabilize, @stabilize_ms)
    Process.send_after(self(), :check_predecessor, @check_pred_ms)
    Process.send_after(self(), :fix_fingers, @fix_fingers_ms)
    {:ok, state}
  end

  @impl true
  # First node creates a ring with itself.
  def handle_call({:join, nil}, _from, state) do
    new_state = %{state | successor: state.id, predecessor: state.id}
    {:reply, :ok, set_finger(new_state, 1, new_state.successor)}
  end

  # Join via a known node and pick its successor.
  def handle_call({:join, known_id}, _from, state) do
    {:ok, found} = GenServer.call(via(known_id), {:find_successor, state.id})
    succ =
      cond do
        found == state.id and known_id != nil -> known_id
        true -> found
      end

    if succ != state.id do
      moved = GenServer.call(via(succ), {:transfer_keys, state.id})
      Enum.each(moved, fn {key_id, value} -> :ets.insert(state.table, {key_id, value}) end)
      GenServer.call(via(succ), {:notify, state.id})
    end

    new_state = %{state | successor: succ, predecessor: nil}
    {:reply, :ok, set_finger(new_state, 1, succ)}
  end

  @impl true
  # Find successor; use fingers to skip ahead.
  def handle_call({:find_successor, key_id}, _from, state) do
    {:reply, find_successor_from_state(state, key_id), state}
  end

  @impl true
  # Update predecessor if candidate is closer.
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

  @impl true
  # Read predecessor id.
  def handle_call(:get_predecessor, _from, state) do
    {:reply, state.predecessor, state}
  end

  @impl true
  # Read basic info for UI/debug.
  def handle_call(:info, _from, state) do
    key_count = :ets.info(state.table, :size)

    {:reply,
     %{id: state.id, successor: state.successor, predecessor: state.predecessor, fingers: state.fingers, key_count: key_count},
     state}
  end

  @impl true
  # Route a DHT put to the responsible node.
  def handle_call({:put, key, value}, _from, state) do
    key_id = hash_key(key)
    {:ok, node_id} = find_successor_from_state(state, key_id)
    route_store(state, node_id, key_id, value)
    {:reply, :ok, state}
  end

  @impl true
  # Route a DHT get to the responsible node.
  def handle_call({:get, key}, _from, state) do
    key_id = hash_key(key)
    {:ok, node_id} = find_successor_from_state(state, key_id)
    {:reply, route_fetch(state, node_id, key_id), state}
  end

  @impl true
  # Store a key locally (no routing).
  def handle_call({:store, key_id, value}, _from, state) do
    :ets.insert(state.table, {key_id, value})
    {:reply, :ok, state}
  end

  @impl true
  # Fetch a key locally (no routing).
  def handle_call({:fetch, key_id}, _from, state) do
    case :ets.lookup(state.table, key_id) do
      [{^key_id, value}] -> {:reply, {:ok, value}, state}
      [] -> {:reply, :not_found, state}
    end
  end

  @impl true
  # Return local keys for debug.
  def handle_call(:dump_keys, _from, state) do
    {:reply, :ets.tab2list(state.table), state}
  end

  @impl true
  # Transfer keys that now belong to new_id.
  def handle_call({:transfer_keys, new_id}, _from, state) do
    pred = state.predecessor || state.id

    moved =
      for {key_id, value} <- :ets.tab2list(state.table),
          in_interval?(key_id, pred, new_id) do
        :ets.delete(state.table, key_id)
        {key_id, value}
      end

    {:reply, moved, state}
  end

  @impl true
  # Update successor pointer directly (used by leave).
  def handle_call({:set_successor, new_succ}, _from, state) do
    new_state = %{state | successor: new_succ}
    {:reply, :ok, set_finger(new_state, 1, new_succ)}
  end

  @impl true
  # Update predecessor pointer directly (used by leave).
  def handle_call({:set_predecessor, new_pred}, _from, state) do
    {:reply, :ok, %{state | predecessor: new_pred}}
  end

  @impl true
  # Graceful leave: move keys and reconnect neighbors.
  def handle_call(:leave, _from, state) do
    if state.successor != state.id do
      Enum.each(:ets.tab2list(state.table), fn {key_id, value} ->
        GenServer.call(via(state.successor), {:store, key_id, value})
      end)
    end

    if state.predecessor && state.predecessor != state.id do
      GenServer.call(via(state.predecessor), {:set_successor, state.successor})
    end

    if state.successor && state.successor != state.id do
      GenServer.call(via(state.successor), {:set_predecessor, state.predecessor})
    end

    {:stop, :normal, :ok, state}
  end

  @impl true
  # Manual stabilize trigger (same logic as timer).
  def handle_cast(:stabilize, state), do: do_stabilize(state)

  @impl true
  # Manual predecessor check trigger (same logic as timer).
  def handle_cast(:check_predecessor, state), do: do_check_predecessor(state)

  @impl true
  # Manual finger fix trigger (same logic as timer).
  def handle_cast(:fix_fingers, state), do: do_fix_fingers(state)

  @impl true
  # Timer-driven stabilize trigger.
  def handle_info(:stabilize, state), do: do_stabilize(state)

  @impl true
  # Timer-driven predecessor check trigger.
  def handle_info(:check_predecessor, state), do: do_check_predecessor(state)

  @impl true
  # Timer-driven finger fix trigger.
  def handle_info(:fix_fingers, state), do: do_fix_fingers(state)

  # Stabilize: verify links with successor and notify it.
  defp do_stabilize(state) do
    state =
      if state.successor == state.id do
        case fallback_successor(state.id) do
          nil -> state
          succ -> %{state | successor: succ}
        end
      else
        state
      end

    pred =
      if state.successor == state.id do
        nil
      else
        GenServer.call(via(state.successor), :get_predecessor)
      end

    new_state =
      cond do
        pred == nil ->
          state

        in_interval?(pred, state.id, state.successor) ->
          %{state | successor: pred}

        true ->
          state
      end

    if new_state.successor != new_state.id do
      GenServer.call(via(new_state.successor), {:notify, new_state.id})
    end

    Process.send_after(self(), :stabilize, @stabilize_ms)
    {:noreply, set_finger(new_state, 1, new_state.successor)}
  end

  # Check that predecessor responds; drop it if not.
  defp do_check_predecessor(state) do
    new_state =
      case state.predecessor do
        nil ->
          state

        pred_id ->
          if pred_id == state.id do
            state
          else
            try do
              _ = GenServer.call(via(pred_id), :get_predecessor)
              state
            catch
              _, _ -> %{state | predecessor: nil}
            end
          end
      end

    Process.send_after(self(), :check_predecessor, @check_pred_ms)
    {:noreply, new_state}
  end

  # Update one finger at a time in round-robin.
  defp do_fix_fingers(state) do
    index = state.next_finger
    start = finger_start(state.id, index)
    {:ok, node_id} = find_successor_from_state(state, start)
    new_state = set_finger(state, index, node_id)
    next_index = if index == @m, do: 1, else: index + 1

    Process.send_after(self(), :fix_fingers, @fix_fingers_ms)
    {:noreply, %{new_state | next_finger: next_index}}
  end

  # Build initial finger table (all point to self).
  defp init_fingers(id) do
    for index <- 1..@m do
      %{start: finger_start(id, index), node: id}
    end
  end

  # Update a single finger entry.
  defp set_finger(state, index, node_id) do
    entry = %{start: finger_start(state.id, index), node: node_id}
    fingers = List.replace_at(state.fingers, index - 1, entry)
    %{state | fingers: fingers}
  end

  # Choose the closest finger that precedes the key.
  defp closest_preceding_node(state, key_id) do
    Enum.reduce_while(Enum.reverse(state.fingers), state.id, fn finger, acc ->
      if finger.node != nil and in_interval?(finger.node, state.id, key_id) do
        {:halt, finger.node}
      else
        {:cont, acc}
      end
    end)
  end

  # Compute successor without sending a call to self.
  defp find_successor_from_state(state, key_id) do
    cond do
      state.successor == state.id ->
        case fallback_successor(state.id) do
          nil -> {:ok, state.id}
          succ -> {:ok, succ}
        end

      in_interval?(key_id, state.id, state.successor) ->
        {:ok, state.successor}

      true ->
        next = closest_preceding_node(state, key_id)

        cond do
          next == state.id and state.successor != state.id ->
            {:ok, state.successor}

          next == state.id ->
            case fallback_successor(state.id) do
              nil -> {:ok, state.id}
              succ -> {:ok, succ}
            end

          true ->
            GenServer.call(via(next), {:find_successor, key_id})
        end
    end
  end

  # Store locally if the target is self, otherwise route.
  defp route_store(state, node_id, key_id, value) do
    if node_id == state.id do
      :ets.insert(state.table, {key_id, value})
      :ok
    else
      GenServer.call(via(node_id), {:store, key_id, value})
    end
  end

  # Fetch locally if the target is self, otherwise route.
  defp route_fetch(state, node_id, key_id) do
    if node_id == state.id do
      case :ets.lookup(state.table, key_id) do
        [{^key_id, value}] -> {:ok, value}
        [] -> :not_found
      end
    else
      GenServer.call(via(node_id), {:fetch, key_id})
    end
  end

  # Compute the start of a finger interval.
  defp finger_start(id, index) do
    rem(id + (1 <<< (index - 1)), ring_size())
  end

  # Hash a key into the identifier space using SHA-1.
  defp hash_key(key) do
    data = :erlang.term_to_binary(key)
    <<hash::unsigned-32, _::binary>> = :crypto.hash(:sha, data)
    rem(hash, ring_size())
  end

  # Check if key is in (start_id, end_id] on the ring.
  defp in_interval?(key_id, start_id, end_id) do
    cond do
      start_id < end_id -> key_id > start_id and key_id <= end_id
      start_id > end_id -> key_id > start_id or key_id <= end_id
      true -> true
    end
  end

  # Find any other node id alive (used as fallback when successor=self).
  defp fallback_successor(self_id) do
    ids =
      Registry.select(ChordSim.NodeRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
      |> Enum.reject(&(&1 == self_id))
      |> Enum.sort()

    case ids do
      [] -> nil
      _ -> Enum.find(ids, fn id -> id > self_id end) || hd(ids)
    end
  end
end
