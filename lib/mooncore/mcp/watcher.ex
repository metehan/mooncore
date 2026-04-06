defmodule Mooncore.MCP.Watcher do
  @moduledoc """
  In-memory log collector for development observability.

  Stores temporary logs in a ring buffer (configurable max size).
  AI agents or the dev UI can add watchers, read logs, and filter by tag.

  Only active when mooncore_dev_tools is enabled:

      config :mooncore, mooncore_dev_tools: true

  ## Usage

      # Log an event (from anywhere in the app)
      Mooncore.MCP.Watcher.log(:lifecycle, %{action: "task.create", phase: :start})
      Mooncore.MCP.Watcher.log(:custom, %{message: "something happened"})

      # Read all logs
      Mooncore.MCP.Watcher.read()

      # Read logs filtered by tag
      Mooncore.MCP.Watcher.read(:lifecycle)

      # Add a watcher — subscribe a PID to receive logs in real-time
      Mooncore.MCP.Watcher.add_watcher(self(), :lifecycle)

      # Clear logs
      Mooncore.MCP.Watcher.clear()
  """

  use GenServer

  @max_logs 1000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    {:ok, %{logs: [], watchers: [], max: @max_logs}}
  end

  @doc "Log an event with a tag. Only stores if mooncore_dev_tools is on."
  def log(tag, data) do
    if Mooncore.mooncore_dev_tools_enabled?() and Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:log, tag, data})
    end
  end

  @doc "Read all logs, optionally filtered by tag. Returns newest first."
  def read(tag \\ nil) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:read, tag})
    else
      []
    end
  end

  @doc "Read logs since a given entry id."
  def read_since(since_id) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:read_since, since_id})
    else
      []
    end
  end

  @doc "Add a watcher PID. It will receive `{:mooncore_log, tag, entry}` messages."
  def add_watcher(pid, tag_filter \\ nil) do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:add_watcher, pid, tag_filter})
    end
  end

  @doc "Remove a watcher PID."
  def remove_watcher(pid) do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:remove_watcher, pid})
    end
  end

  @doc "Clear all logs."
  def clear do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, :clear)
    end
  end

  @doc "Get watcher count."
  def watcher_count do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :watcher_count)
    else
      0
    end
  end

  # Server callbacks

  def handle_cast({:log, tag, data}, state) do
    entry = %{
      id: System.unique_integer([:positive, :monotonic]),
      tag: tag,
      data: data,
      timestamp: :os.system_time(:milli_seconds)
    }

    # Notify watchers
    Enum.each(state.watchers, fn {pid, tag_filter} ->
      if is_nil(tag_filter) or tag_filter == tag do
        send(pid, {:mooncore_log, tag, entry})
      end
    end)

    # Ring buffer — drop oldest when full
    logs = [entry | state.logs] |> Enum.take(state.max)

    {:noreply, %{state | logs: logs}}
  end

  def handle_cast({:add_watcher, pid, tag_filter}, state) do
    Process.monitor(pid)
    watchers = [{pid, tag_filter} | state.watchers] |> Enum.uniq_by(&elem(&1, 0))
    {:noreply, %{state | watchers: watchers}}
  end

  def handle_cast({:remove_watcher, pid}, state) do
    watchers = Enum.reject(state.watchers, fn {p, _} -> p == pid end)
    {:noreply, %{state | watchers: watchers}}
  end

  def handle_cast(:clear, state) do
    {:noreply, %{state | logs: []}}
  end

  def handle_call({:read, nil}, _from, state) do
    {:reply, state.logs, state}
  end

  def handle_call({:read, tag}, _from, state) do
    filtered = Enum.filter(state.logs, fn e -> e.tag == tag end)
    {:reply, filtered, state}
  end

  def handle_call({:read_since, since_id}, _from, state) do
    logs = Enum.take_while(state.logs, fn e -> e.id > since_id end)
    {:reply, logs, state}
  end

  def handle_call(:watcher_count, _from, state) do
    {:reply, length(state.watchers), state}
  end

  # Clean up dead watchers
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    watchers = Enum.reject(state.watchers, fn {p, _} -> p == pid end)
    {:noreply, %{state | watchers: watchers}}
  end

  def handle_info(_, state), do: {:noreply, state}
end
