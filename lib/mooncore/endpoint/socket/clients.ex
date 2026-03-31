defmodule Mooncore.Endpoint.Socket.Clients do
  @moduledoc """
  GenServer that tracks WebSocket client PIDs organized by group and channel.

  State structure:

      %{
        "group_key" => %{
          "@username" => [pid1],
          "main:default" => [pid1, pid2],
          "chat:default" => [pid3]
        }
      }

  ## Usage

  Started automatically by `Mooncore.Application` for each pool in config.
  """
  use GenServer

  def start_link(name: name) do
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def init(_) do
    {:ok, %{}}
  end

  def add_member(group, channel, pid, state_name \\ :default) do
    GenServer.cast(state_name, {:add_member, group, channel, pid})
  end

  def remove_member(group, channels, pid, state_name \\ :default) do
    GenServer.cast(state_name, {:remove_member, group, channels, pid})
  end

  def list_all(state_name \\ :default) do
    GenServer.call(state_name, :get_online_list)
  end

  def list_group(group, state_name \\ :default) do
    Map.get(GenServer.call(state_name, :get_online_list), group, %{})
  end

  def list_members(group, channel, state_name \\ :default) do
    case get_in(GenServer.call(state_name, :get_online_list), [group, channel]) do
      nil -> []
      pids -> pids
    end
  end

  def handle_cast({:add_member, group, channel, pid}, state) do
    updated_state =
      case get_in(state, [group, channel]) do
        nil ->
          put_in(state, Enum.map([group, channel], &Access.key(&1, %{})), [pid])

        pids ->
          put_in(state, [group, channel], Enum.uniq([pid | pids]))
      end

    {:noreply, updated_state}
  end

  def handle_cast({:remove_member, group, channels, pid}, state) do
    updated_state =
      Enum.reduce(channels, state, fn channel, acc_state ->
        case get_in(acc_state, [group, channel]) do
          nil ->
            acc_state

          pids ->
            new_pids = List.delete(pids, pid)

            if new_pids == [] do
              {_, new_state} = pop_in(acc_state, [group, channel])
              new_state
            else
              put_in(acc_state, [group, channel], new_pids)
            end
        end
      end)
      |> Enum.reject(fn {_k, v} -> v == %{} end)
      |> Map.new()

    {:noreply, updated_state}
  end

  def handle_call(:get_online_list, _from, state) do
    {:reply, state, state}
  end
end
