defmodule Mooncore.Endpoint.Socket do
  @moduledoc """
  WebSocket pub/sub and message handling.

  Provides `publish/3` for broadcasting to connected clients
  and `receive/2` for processing incoming WebSocket messages through the action pipeline.
  """

  alias Mooncore.Endpoint.Socket.Clients

  @doc """
  Publish a message to all clients in the given channels.

  ## Examples

      # Broadcast to default channel
      Mooncore.Endpoint.Socket.publish("domain_key", {"record", data})

      # Broadcast to specific channels
      Mooncore.Endpoint.Socket.publish("domain_key", {"event", data}, ["main:default", "main:branch1"])
  """
  def publish(group, {name, message}, channels \\ ["main:default"]) do
    message = if is_map(message), do: Map.delete(message, "password"), else: message

    for channel <- channels do
      Clients.list_members(group, channel)
      |> Enum.each(fn pid -> send(pid, {:push, [name, message]}) end)
    end

    message
  end

  @doc """
  Handle an incoming WebSocket message through the action pipeline.
  Builds a request map from the socket state and message, executes the action,
  and pushes the response back to the client.
  """
  def receive(state, message) do
    response =
      Mooncore.Action.execute(
        message["action"],
        %{
          auth: state.auth,
          action: message["action"],
          rayid: message["rayid"],
          socket_pid: state.pid,
          params: message
        }
      )
      |> Mooncore.Action.format_response()

    send(state.pid, {:push, ["response", response, message["rayid"]]})
  end
end
