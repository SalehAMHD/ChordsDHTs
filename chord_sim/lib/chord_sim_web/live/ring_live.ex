defmodule ChordSimWeb.RingLive do
  use ChordSimWeb, :live_view

  @refresh_ms 1_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_defaults()
      |> load_state()

    if connected?(socket) do
      Process.send_after(self(), :refresh, @refresh_ms)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    socket = load_state(socket)
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, socket}
  end

  @impl true
  def handle_event("add_node", _params, socket) do
    nodes = list_nodes()
    new_id = next_available_id(nodes)

    socket =
      case new_id do
        nil ->
          assign(socket, notice: "No free ids in the ring")

        id ->
          case ChordSim.NodeSupervisor.start_node(id) do
            {:ok, _pid} ->
              known = List.first(nodes)
              :ok = ChordSim.Node.join(id, known)
              assign(socket, notice: "Node #{id} joined")

            {:error, _} ->
              assign(socket, notice: "Failed to start node #{id}")
          end
      end

    {:noreply, load_state(socket)}
  end

  @impl true
  def handle_event("remove_node", _params, socket) do
    nodes = list_nodes()
    selected_id = socket.assigns.selected_id

    socket =
      cond do
        selected_id == nil ->
          assign(socket, notice: "Select a node first")

        selected_id in nodes ->
          _ = safe_call(fn -> ChordSim.Node.leave(selected_id) end)
          assign(socket, notice: "Node #{selected_id} left")

        true ->
          assign(socket, notice: "Node #{selected_id} not found")
      end

    {:noreply, load_state(socket)}
  end

  @impl true
  def handle_event("select_node", %{"id" => id}, socket) do
    {:noreply, assign(socket, selected_id: parse_id(id))}
  end

  @impl true
  def handle_event("set_entry", %{"entry_id" => id}, socket) do
    {:noreply, assign(socket, entry_id: parse_id(id))}
  end

  @impl true
  def handle_event("put", %{"key" => key, "value" => value}, socket) do
    entry_id = socket.assigns.entry_id

    socket =
      cond do
        entry_id == nil ->
          assign(socket, notice: "Add a node first")

        key == "" or value == "" ->
          assign(socket, notice: "Key and value are required")

        true ->
          :ok = ChordSim.Node.put(entry_id, key, value)
          key_id = ChordSim.Node.hash_id(key)
          {:ok, owner} = ChordSim.Node.find_successor(entry_id, key_id)
          assign(socket, notice: "Stored on node #{owner} (key id #{key_id})")
      end

    {:noreply, load_state(socket)}
  end

  @impl true
  def handle_event("get", %{"key" => key}, socket) do
    entry_id = socket.assigns.entry_id

    socket =
      cond do
        entry_id == nil ->
          assign(socket, notice: "Add a node first")

        key == "" ->
          assign(socket, notice: "Key is required")

        true ->
          key_id = ChordSim.Node.hash_id(key)
          {:ok, owner} = ChordSim.Node.find_successor(entry_id, key_id)

          case ChordSim.Node.get(entry_id, key) do
            {:ok, value} ->
              assign(socket, notice: "Found #{inspect(value)} on node #{owner}")

            :not_found ->
              assign(socket, notice: "Not found (responsible node #{owner})")
          end
      end

    {:noreply, load_state(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="chord-app">
      <header class="chord-hero fade-in">
        <div>
          <p class="chord-kicker">Project CHORD DHT & simulation</p>
          <h1 class="chord-title">Chord Ring Control Room</h1>
          <p class="chord-subtitle">
            Visualize a distributed hash table, add nodes, and track where keys live in the ring.
          </p>
        </div>
        <div class="chord-metrics">
          <div class="metric-card">
            <span class="metric-label">Nodes</span>
            <span class="metric-value"><%= @nodes_count %></span>
          </div>
          <div class="metric-card">
            <span class="metric-label">m bits</span>
            <span class="metric-value"><%= @m %></span>
          </div>
          <div class="metric-card">
            <span class="metric-label">Ring size</span>
            <span class="metric-value"><%= @ring_size %></span>
          </div>
        </div>
      </header>

      <section class="chord-actions fade-in" style="--delay: 80ms;">
        <button class="chord-btn" phx-click="add_node">Add node</button>
        <button class="chord-btn ghost" phx-click="remove_node">Remove selected</button>
        <div class="chord-select">
          <label for="selected">Selected node</label>
          <select id="selected" name="id" phx-change="select_node">
            <option value="">None</option>
            <%= for id <- @nodes do %>
              <option value={id} selected={@selected_id == id}><%= id %></option>
            <% end %>
          </select>
        </div>
        <div class="chord-select">
          <label for="entry">Entry node</label>
          <select id="entry" name="entry_id" phx-change="set_entry">
            <option value="">None</option>
            <%= for id <- @nodes do %>
              <option value={id} selected={@entry_id == id}><%= id %></option>
            <% end %>
          </select>
        </div>
        <div class="chord-notice"><%= @notice %></div>
      </section>

      <section class="chord-grid">
        <div class="panel ring-panel fade-in" style="--delay: 140ms;">
          <div class="panel-head">
            <h2>Ring map</h2>
            <p>Each dot is a node placed on a circular layout.</p>
          </div>
          <div class="ring-wrap">
            <div class="ring-core"></div>
            <%= for {node, index} <- Enum.with_index(@ring_points) do %>
              <button
                class={"node-dot #{if @selected_id == node.id, do: "is-selected", else: ""}"}
                style={"left: #{node.x}%; top: #{node.y}%; --delay: #{index * 40}ms;"}
                phx-click="select_node"
                phx-value-id={node.id}
              >
                <span><%= node.id %></span>
              </button>
            <% end %>
          </div>
        </div>

        <div class="panel control-panel fade-in" style="--delay: 200ms;">
          <div class="panel-head">
            <h2>Key actions</h2>
            <p>Store or fetch values using any entry node.</p>
          </div>

          <form class="chord-form" phx-submit="put">
            <label>Key</label>
            <input type="text" name="key" value={@put_key} placeholder="e.g. song:42" />
            <label>Value</label>
            <input type="text" name="value" value={@put_value} placeholder="e.g. Cmaj" />
            <button class="chord-btn" type="submit">Put</button>
          </form>

          <form class="chord-form" phx-submit="get">
            <label>Key</label>
            <input type="text" name="key" value={@get_key} placeholder="e.g. song:42" />
            <button class="chord-btn ghost" type="submit">Get</button>
          </form>
        </div>
      </section>

      <section class="panel data-panel fade-in" style="--delay: 260ms;">
        <div class="panel-head">
          <h2>Node details</h2>
          <p>Successor, predecessor, fingers, and local keys.</p>
        </div>

        <div class="detail-grid">
          <div>
            <h3>Nodes</h3>
            <table class="chord-table">
              <thead>
                <tr>
                  <th>ID</th>
                  <th>Successor</th>
                  <th>Predecessor</th>
                  <th>Keys</th>
                </tr>
              </thead>
              <tbody>
                <%= for id <- @nodes do %>
                  <% info = Map.get(@node_info, id) %>
                  <tr class={if @selected_id == id, do: "is-selected", else: ""}>
                    <td><%= id %></td>
                    <td><%= if info, do: info.successor, else: "-" %></td>
                    <td><%= if info, do: info.predecessor, else: "-" %></td>
                    <td><%= if info, do: info.key_count, else: 0 %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <div>
            <h3>Finger table</h3>
            <table class="chord-table">
              <thead>
                <tr>
                  <th>Index</th>
                  <th>Start</th>
                  <th>Node</th>
                </tr>
              </thead>
              <tbody>
                <%= if @selected_info do %>
                  <%= for {finger, idx} <- Enum.with_index(@selected_info.fingers, 1) do %>
                    <tr>
                      <td><%= idx %></td>
                      <td><%= finger.start %></td>
                      <td><%= finger.node %></td>
                    </tr>
                  <% end %>
                <% else %>
                  <tr>
                    <td colspan="3">Select a node</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <div>
            <h3>Local keys</h3>
            <div class="keys-list">
              <%= if @selected_keys == [] do %>
                <p>No keys stored.</p>
              <% else %>
                <%= for {key_id, value} <- @selected_keys do %>
                  <div class="key-pill">
                    <span class="key-id"><%= key_id %></span>
                    <span class="key-value"><%= inspect(value) %></span>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end

  defp assign_defaults(socket) do
    assign(socket,
      nodes: [],
      nodes_count: 0,
      node_info: %{},
      ring_points: [],
      selected_id: nil,
      selected_info: nil,
      selected_keys: [],
      entry_id: nil,
      notice: "",
      put_key: "",
      put_value: "",
      get_key: "",
      m: ChordSim.Node.m(),
      ring_size: ChordSim.Node.ring_size()
    )
  end

  defp load_state(socket) do
    nodes = list_nodes()
    nodes_count = length(nodes)
    selected_id = pick_id(nodes, socket.assigns.selected_id)
    entry_id = pick_id(nodes, socket.assigns.entry_id)
    node_info = build_node_info(nodes)
    selected_info = Map.get(node_info, selected_id)
    selected_keys = if selected_id, do: safe_dump(selected_id), else: []

    ring_points =
      if nodes == [] do
        []
      else
        nodes
        |> Enum.with_index()
        |> Enum.map(fn {id, idx} ->
          angle = 2 * :math.pi() * idx / max(nodes_count, 1)
          %{id: id, x: 50 + 38 * :math.cos(angle), y: 50 + 38 * :math.sin(angle)}
        end)
      end

    assign(socket,
      nodes: nodes,
      nodes_count: nodes_count,
      node_info: node_info,
      ring_points: ring_points,
      selected_id: selected_id,
      selected_info: selected_info,
      selected_keys: selected_keys,
      entry_id: entry_id
    )
  end

  defp list_nodes do
    ChordSim.NodeSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.reduce([], fn
      {_child_id, pid, :worker, _modules}, acc when is_pid(pid) ->
        case :sys.get_state(pid) do
          %{id: id} -> [id | acc]
          _ -> acc
        end

      _, acc ->
        acc
    end)
    |> Enum.sort()
  end

  defp build_node_info(nodes) do
    nodes
    |> Enum.map(fn id ->
      {id, safe_info(id)}
    end)
    |> Enum.into(%{})
  end

  defp safe_info(id) do
    safe_call(fn -> ChordSim.Node.info(id) end)
  end

  defp safe_dump(id) do
    safe_call(fn -> ChordSim.Node.dump_keys(id) end) || []
  end

  defp safe_call(fun) do
    try do
      fun.()
    catch
      _, _ -> nil
    end
  end

  defp pick_id([], _current), do: nil

  defp pick_id(nodes, current) do
    if current in nodes do
      current
    else
      List.first(nodes)
    end
  end

  defp parse_id(""), do: nil

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, _} -> id
      :error -> nil
    end
  end

  defp next_available_id(nodes) do
    ring = ChordSim.Node.ring_size()
    start = if nodes == [], do: 1, else: Enum.max(nodes) + 1

    Enum.find(0..(ring - 1), fn offset ->
      id = rem(start + offset, ring)
      id not in nodes
    end)
  end
end
