defmodule Mooncore.Endpoint.Socket.Clients do
  @moduledoc """
  Tracks WebSocket client PIDs organized by group and channel.

  Uses an ETS `:bag` table for lock-free concurrent reads — `list_members/3`
  reads directly from ETS without going through the GenServer. Writes
  (add/remove) are serialized through the GenServer for consistency.

  ETS table name is `:mooncore_{pool}` (e.g. `:mooncore_default`).

  ## Usage

  Started automatically by `Mooncore.Application` for each pool in config.
  """
  use GenServer

  def start_link(name: name) do
    GenServer.start_link(__MODULE__, name, name: name)
  end

  def init(name) do
    table = :ets.new(table_name(name), [:bag, :public, :named_table, {:read_concurrency, true}])
    {:ok, %{table: table}}
  end

  # ── Public API ──

  def add_member(group, channel, pid, pool \\ :default) do
    GenServer.cast(pool, {:add_member, group, channel, pid})
  end

  def remove_member(group, channels, pid, pool \\ :default) do
    GenServer.cast(pool, {:remove_member, group, channels, pid})
  end

  @doc "List PIDs for a channel. Reads directly from ETS — no GenServer call."
  def list_members(group, channel, pool \\ :default) do
    :ets.lookup(table_name(pool), {group, channel})
    |> Enum.map(fn {_key, pid} -> pid end)
  end

  @doc "All channels and PIDs for a group. Reads from ETS."
  def list_group(group, pool \\ :default) do
    :ets.tab2list(table_name(pool))
    |> Enum.filter(fn {{g, _ch}, _pid} -> g == group end)
    |> Enum.reduce(%{}, fn {{_g, ch}, pid}, acc ->
      Map.update(acc, ch, [pid], &[pid | &1])
    end)
  end

  @doc "Full state as a nested map. Reads from ETS."
  def list_all(pool \\ :default) do
    :ets.tab2list(table_name(pool))
    |> Enum.reduce(%{}, fn {{group, channel}, pid}, acc ->
      acc
      |> Map.update(group, %{channel => [pid]}, fn g ->
        Map.update(g, channel, [pid], &[pid | &1])
      end)
    end)
  end

  defp table_name(pool), do: :"mooncore_#{pool}"

  # ── GenServer callbacks (writes only) ──

  def handle_cast({:add_member, group, channel, pid}, state) do
    # :bag ignores duplicate {key, value} pairs — no uniq needed
    :ets.insert(state.table, {{group, channel}, pid})
    {:noreply, state}
  end

  def handle_cast({:remove_member, group, channels, pid}, state) do
    Enum.each(channels, fn channel ->
      :ets.delete_object(state.table, {{group, channel}, pid})
    end)

    {:noreply, state}
  end
end
