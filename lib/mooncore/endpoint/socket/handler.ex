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

  @anon_group "_anon"
  @anon_channel "ws:pending"

  ## Init

  def init(conn: conn) do
    auth = conn.assigns[:auth] || Map.get(conn, :auth, nil)

    listening =
      if auth do
        # Only subscribe to the personal channel automatically.
        # The scope channel (main:{scope}) must be joined explicitly
        # to avoid putting all clients in one massive channel.
        Clients.add_member(auth["dkey"], "@#{auth["user"]}", self())
        ["@#{auth["user"]}"]
      else
        Clients.add_member(@anon_group, @anon_channel, self())
        []
      end

    {:ok,
     %{
       conn: conn,
       auth: auth,
       pid: self(),
       listening: listening,
       anon: is_nil(auth)
     }}
  end

  ## Helpers

  defp reply(msg, state) do
    {:reply, :ok, {:text, msg}, state}
  end

  defp reply(name, msg, state) do
    {:reply, :ok, {:text, Jason.encode!([name, msg])}, state}
  end

  defp log_socket(direction, state, payload) do
    if Mooncore.mooncore_dev_tools_enabled?() do
      Mooncore.MCP.Watcher.log(:socket, %{
        direction: direction,
        pid: inspect(self()),
        user: state.auth && state.auth["user"],
        dkey: state.auth && state.auth["dkey"],
        channels: state.listening,
        payload: payload
      })
    end
  end

  ## Text Messages

  def handle_in({"ping", [opcode: :text]}, state) do
    log_socket(:in, state, "ping")
    reply("pong", state)
  end

  def handle_in({"time", [opcode: :text]}, state) do
    log_socket(:in, state, "time")
    reply("server_time", :os.system_time(:milli_seconds), state)
  end

  def handle_in({"channel_list", [opcode: :text]}, state) do
    log_socket(:in, state, "channel_list")
    reply("channel_list", state.listening, state)
  end

  def handle_in({"quit", [opcode: :text]}, state) do
    log_socket(:in, state, "quit")
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
    log_socket(:in, state, ["jwt", "<redacted>"])

    case Mooncore.Auth.Token.solve(jwt) do
      {:ok, auth} ->
        # Remove from anon bucket if this was an unauthenticated connection
        if state.anon do
          Clients.remove_member(@anon_group, [@anon_channel], self())
        end

        # Only auto-subscribe to personal channel.
        # Scope channel (main:{scope}) requires explicit ["join", "main"].
        Clients.add_member(auth["dkey"], "@#{auth["user"]}", self())
        personal = "@#{auth["user"]}"

        listening =
          if(personal in state.listening,
            do: state.listening,
            else: [personal | state.listening]
          )

        state = Map.merge(state, %{auth: auth, anon: false, listening: listening})

        reply("jwt", auth, state)

      _ ->
        reply("jwt", "jwt_failed", state)
    end
  end

  # Channel join
  def handle_map(["join", channel], state) do
    log_socket(:in, state, ["join", channel])
    roles = (state.auth && state.auth["roles"]) || []

    # "main" is the scope channel — allowed if authenticated
    # Custom channels require role "channel_{name}"
    allowed =
      state.auth &&
        (channel == "main" or Enum.member?(roles, "channel_#{channel}"))

    if allowed do
      scoped_channel = "#{channel}:#{state.auth["scope"]}"
      Clients.add_member(state.auth["dkey"], scoped_channel, self())

      state =
        if scoped_channel in state.listening,
          do: state,
          else: %{state | listening: [scoped_channel | state.listening]}

      reply("channel_list", state.listening, state)
    else
      reply("channel_list", state.listening, state)
    end
  end

  # Channel leave
  def handle_map(["leave", channel], state) do
    log_socket(:in, state, ["leave", channel])

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
    log_socket(:in, state, message)
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

  ## Cleanup on disconnect

  def terminate(_reason, state) do
    if state.anon do
      Clients.remove_member(@anon_group, [@anon_channel], self())
    else
      if state.auth do
        Clients.remove_member(state.auth["dkey"], state.listening, self())
      end
    end

    :ok
  end

  ## Channel management via process messages

  def handle_info({:listen, group, channel}, state) do
    Clients.add_member(group, channel, self())

    state =
      if channel in state.listening,
        do: state,
        else: %{state | listening: [channel | state.listening]}

    reply("channel_list", state.listening, state)
  end

  def handle_info({:unlisten, group, channel}, state) do
    Clients.remove_member(group, [channel], self())

    state =
      Map.merge(state, %{listening: Enum.reject(state.listening, fn ch -> ch == channel end)})

    reply("channel_list", state.listening, state)
  end
end
