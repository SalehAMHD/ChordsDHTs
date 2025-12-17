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
  def get_predecessor(id), do: GenServer.call(via(id), :get_predecessor)
  def stabilize(id), do: GenServer.cast(via(id), :stabilize)
  def check_predecessor(id), do: GenServer.cast(via(id), :check_predecessor)
  def put(id, key, value), do: GenServer.call(via(id), {:put, key, value})
  def get(id, key), do: GenServer.call(via(id), {:get, key})

  ## Callbacks
  @impl true
  def init(id) do
    table = :ets.new(String.to_atom("node_#{id}_table"), [:set, :protected, :named_table])
    state = %{id: id, successor: id, predecessor: nil, table: table}
    Process.send_after(self(), :stabilize, 1_000)
    Process.send_after(self(), :check_predecessor, 2_000)
    {:ok, state}
  end

  @impl true
  # Premier noeud : boucle sur lui-même.
  def handle_call({:join, nil}, _from, state) do
    {:reply, :ok, %{state | successor: state.id, predecessor: state.id}}
  end

  # Rejoint un anneau existant via un noeud connu.
  def handle_call({:join, known_id}, _from, state) do
    {:ok, succ} = GenServer.call(via(known_id), {:find_successor, state.id})
    GenServer.call(via(succ), {:notify, state.id})
    {:reply, :ok, %{state | successor: succ, predecessor: nil}}
  end

  # Cherche le successeur responsable d'une cle.
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

  # Met a jour le predecesseur si le candidat est plus proche.
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

  # Renvoie le predecesseur actuel.
  def handle_call(:get_predecessor, _from, state) do
    {:reply, state.predecessor, state}
  end

  # Stocke une paire cle/valeur localement.
  def handle_call({:put, key, value}, _from, state) do
    :ets.insert(state.table, {key, value})
    {:reply, :ok, state}
  end

  # Recupere une valeur par cle si elle existe.
  def handle_call({:get, key}, _from, state) do
    case :ets.lookup(state.table, key) do
      [{^key, value}] -> {:reply, {:ok, value}, state}
      [] -> {:reply, :not_found, state}
    end
  end

  @impl true
  # Verifie periodiquement si un noeud s'est insere entre moi et mon successeur.
  def handle_cast(:stabilize, state) do
    pred =
      case GenServer.call(via(state.successor), :get_predecessor) do
        nil -> nil
        value -> value
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

    GenServer.call(via(new_state.successor), {:notify, new_state.id})
    Process.send_after(self(), :stabilize, 1_000)
    {:noreply, new_state}
  end

  # Nettoie le predecesseur s'il ne repond plus.
  def handle_cast(:check_predecessor, state) do
    new_state =
      case state.predecessor do
        nil ->
          state

        pred_id ->
          try do
            _ = GenServer.call(via(pred_id), :get_predecessor)
            state
          catch
            _, _ -> %{state | predecessor: nil}
          end
      end

    Process.send_after(self(), :check_predecessor, 2_000)
    {:noreply, new_state}
  end

  defp in_interval?(key, start_id, end_id) do
    cond do
      start_id < end_id -> key > start_id and key <= end_id
      start_id > end_id -> key > start_id or key <= end_id
      true -> true
    end
  end
end
