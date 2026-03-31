defmodule Mooncore.Endpoint.Socket.Handler do
  @moduledoc """
  WebSocket connection handler.

  Manages WebSocket connections: authentication, channel subscriptions,
  message routing, and binary protocol support.

  ## Connection Flow

  1. Client connects to `/ws` — upgrade via WebSockAdapter
  2. Handler.init/1 — sets up state, subscribes to user channels if authed
  3. Client sends messages — text (JSON) or binary (metadata + payload)
  4. Handler routes to action pipeline or handles control messages

  ## Special Messages

  - `"ping"` → `"pong"`
  - `"time"` → server timestamp
  - `"channel_list"` → list of subscribed channels
  - `"quit"` → close connection
  - `["jwt", token]` → authenticate and subscribe to channels
  - `["join", channel]` → subscribe to channel (requires role)
  - `["leave", channel]` → unsubscribe from channel
  - Any JSON object with `"action"` key → dispatched to action pipeline
  """

  alias Mooncore.Endpoint.Socket.Clients
  alias Mooncore.Endpoint.Socket

  ## Init

  def init(conn: conn) do
    auth = conn.assigns[:auth] || Map.get(conn, :auth, nil)

    listening =
      if auth do
        Clients.add_member(auth["dkey"], "@#{auth["user"]}", self())
        Clients.add_member(auth["dkey"], "main:#{auth["scope"]}", self())
        ["@#{auth["user"]}", "main:#{auth["scope"]}"]
      else
        []
      end

    {:ok,
     %{
       conn: conn,
       auth: auth,
       pid: self(),
       listening: listening
     }}
  end

  ## Helpers

  defp reply(msg, state) do
    {:reply, :ok, {:text, msg}, state}
  end

  defp reply(name, msg, state) do
    {:reply, :ok, {:text, Jason.encode!([name, msg])}, state}
  end

  ## Text Messages

  def handle_in({"ping", [opcode: :text]}, state) do
    reply("pong", state)
  end

  def handle_in({"time", [opcode: :text]}, state) do
    reply("server_time", :os.system_time(:milli_seconds), state)
  end

  def handle_in({"channel_list", [opcode: :text]}, state) do
    reply("channel_list", state.listening, state)
  end

  def handle_in({"quit", [opcode: :text]}, state) do
    {:stop, :normal, state}
  end

  def handle_in({text, [opcode: :text]}, state) do
    case Jason.decode(text) do
      {:ok, json} ->
        handle_map(json, state)

      {:error, _} ->
        reply("socket_error", "json_decode_failed", state)
    end
  end

  ## Binary Messages

  def handle_in({binary, [opcode: :binary]}, state) do
    <<metadata_length::little-16, rest::binary>> = binary
    <<metadata::binary-size(metadata_length), bind::binary>> = rest

    case Jason.decode(metadata) do
      {:ok, metadata} ->
        handle_map(metadata |> Map.put("bind", bind), state)

      {:error, _} ->
        reply("socket_error", "json_decode_failed", state)
    end
  end

  ## JSON Message Routing

  # JWT authentication
  def handle_map(["jwt", jwt], state) do
    case Mooncore.Auth.Token.solve(jwt) do
      {:ok, auth} ->
        Clients.add_member(auth["dkey"], "@#{auth["user"]}", self())
        Clients.add_member(auth["dkey"], "main:#{auth["scope"]}", self())

        state =
          Map.merge(state, %{
            auth: auth,
            listening: Enum.uniq(state.listening ++ ["@#{auth["user"]}", "main:#{auth["scope"]}"])
          })

        reply("jwt", auth, state)

      _ ->
        reply("jwt", "jwt_failed", state)
    end
  end

  # Channel join
  def handle_map(["join", channel], state) do
    roles = (state.auth && state.auth["roles"]) || []

    if Enum.member?(roles, "channel_#{channel}") do
      scoped_channel = "#{channel}:#{state.auth["scope"]}"
      Clients.add_member(state.auth["dkey"], scoped_channel, self())
      state = Map.merge(state, %{listening: Enum.uniq(state.listening ++ [scoped_channel])})
      reply("channel_list", state.listening, state)
    else
      reply("channel_list", state.listening, state)
    end
  end

  # Channel leave
  def handle_map(["leave", channel], state) do
    if state.auth do
      scoped_channel = "#{channel}:#{state.auth["scope"]}"
      Clients.remove_member(state.auth["dkey"], [scoped_channel], self())

      state =
        Map.merge(state, %{
          listening: Enum.reject(state.listening, fn ch -> ch == scoped_channel end)
        })

      reply("channel_list", state.listening, state)
    else
      {:ok, state}
    end
  end

  # Forward any other message to Socket.receive (action pipeline)
  def handle_map(message, state) when is_map(message) do
    Socket.receive(state, message)
    {:ok, state}
  end

  def handle_map(_message, state) do
    {:ok, state}
  end

  ## Push messages to client

  def handle_info({:push, message}, state) do
    content =
      case Jason.encode(message) do
        {:ok, json} -> json
        _ -> inspect(message)
      end

    {:reply, :ok, {:text, content}, state}
  end

  def handle_info({:log, message}, state) do
    content = if is_binary(message), do: message, else: Jason.encode!(message)
    {:reply, :ok, {:text, content}, state}
  end

  ## Channel management via process messages

  def handle_info({:listen, group, channel}, state) do
    Clients.add_member(group, channel, self())
    state = Map.merge(state, %{listening: Enum.uniq(state.listening ++ [channel])})
    reply("channel_list", state.listening, state)
  end

  def handle_info({:unlisten, group, channel}, state) do
    Clients.remove_member(group, [channel], self())

    state =
      Map.merge(state, %{listening: Enum.reject(state.listening, fn ch -> ch == channel end)})

    reply("channel_list", state.listening, state)
  end

  ## Termination

  def terminate(_reason, state) do
    if state.auth do
      Clients.remove_member(state.auth["dkey"], state.listening, self())
    end

    {:ok, state}
  end
end
