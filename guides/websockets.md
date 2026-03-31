# WebSockets

Mooncore treats WebSockets as a first-class transport. The same actions that work over HTTP work over WebSocket, and the framework adds channels, pub/sub, and binary protocol support on top.

## Setup

Add the WebSocket upgrade route to your router:

```elixir
defmodule MyApp.Router do
  use Plug.Router

  plug Mooncore.Auth.Plug
  # ... other plugs ...
  plug :match
  plug :dispatch

  get "/ws" do
    conn
    |> WebSockAdapter.upgrade(
      Mooncore.Endpoint.Socket.Handler,
      [conn: conn],
      timeout: 60_000
    )
    |> halt()
  end
end
```

## Connection Lifecycle

### 1. Connect

The client opens a WebSocket connection to `/ws`. If the HTTP request has a valid JWT in the `Authorization` header (processed by `Mooncore.Auth.Plug`), the connection is authenticated immediately.

### 2. Authenticate (Optional)

If the client didn't authenticate during the HTTP upgrade, it can send authentication over the WebSocket:

```json
["jwt", "eyJhbGciOiJSUzI1NiIs..."]
```

Response:

```json
["jwt", {"user": "alice", "app": "myapp", "roles": ["user"], ...}]
```

### 3. Send Actions

Any JSON object with an `"action"` key is dispatched through the action pipeline:

```json
{"action": "task.create", "title": "My Task", "rayid": "abc-123"}
```

Response (pushed back to the client):

```json
["response", {"ok": true, "task": {...}}, "abc-123"]
```

The `rayid` is a client-generated correlation ID — it's echoed back so the client can match responses to requests.

### 4. Close

The client sends `"quit"` or closes the connection. The handler cleans up channel subscriptions and removes the PID from the client registry.

## Control Messages

These special messages are handled directly by the socket handler:

| Message | Response | Description |
|---------|----------|-------------|
| `"ping"` | `"pong"` | Keep-alive |
| `"time"` | `["server_time", 1711827600000]` | Server timestamp (milliseconds) |
| `"channel_list"` | `["channel_list", ["@alice", "main:default"]]` | List subscribed channels |
| `"quit"` | Connection closed | Graceful disconnect |

## Channels

Channels are named groups that clients can subscribe to. Messages published to a channel are broadcast to all subscribed clients.

### Default Channels

When a client authenticates, they're automatically subscribed to:
- `@{username}` — personal channel (e.g., `@alice`)
- `main:{scope}` — scope channel (e.g., `main:default`)

### Joining Channels

Clients can join additional channels if they have the corresponding role:

```json
["join", "chat"]
```

The handler checks for a role named `channel_chat`. If the user has it, they're subscribed to `chat:{scope}`.

### Leaving Channels

```json
["leave", "chat"]
```

### Channel Scoping

All channels are scoped per domain key (`dkey`). When you publish to a channel, only clients in the same domain group receive the message. This provides tenant isolation.

## Publishing Messages

From anywhere in your application code, broadcast to connected clients:

```elixir
# Publish to default channel
Mooncore.Endpoint.Socket.publish("acme-corp", {"task_created", %{id: "123", title: "New Task"}})

# Publish to specific channels
Mooncore.Endpoint.Socket.publish("acme-corp", {"notification", %{message: "Hello"}}, ["main:default", "main:branch1"])

# Publish to a specific user
Mooncore.Endpoint.Socket.publish("acme-corp", {"dm", %{from: "bob", text: "Hi!"}}, ["@alice"])
```

The first argument is the domain key (`dkey`), which determines which client pool to search in.

The second argument is a `{name, data}` tuple. The name helps clients identify the message type.

Messages with a `"password"` key are automatically sanitized — the password field is stripped before broadcasting.

## Binary Protocol

The WebSocket handler supports a binary protocol for sending files, images, or any binary data alongside JSON metadata:

### Binary Message Format

```
[2 bytes: metadata_length (little-endian)] [metadata_length bytes: JSON metadata] [remaining bytes: binary payload]
```

### Sending Binary Data (Client)

```javascript
// JavaScript example
const metadata = JSON.stringify({
  action: "file.upload",
  filename: "photo.jpg",
  rayid: "upload-1"
});

const metadataBytes = new TextEncoder().encode(metadata);
const header = new Uint16Array([metadataBytes.length]);

const message = new Uint8Array([
  ...new Uint8Array(header.buffer),
  ...metadataBytes,
  ...fileBytes
]);

ws.send(message);
```

### Receiving Binary Data (Handler)

In your action handler, the binary payload is available as `req[:params]["bind"]`:

```elixir
defmodule MyApp.Action.File do
  def upload(req) do
    binary_data = req[:params]["bind"]
    filename = req[:params]["filename"]

    File.write!("/uploads/#{filename}", binary_data)
    %{ok: true, filename: filename, size: byte_size(binary_data)}
  end
end
```

## Client Registry

Mooncore tracks connected WebSocket clients using a per-pool GenServer (`Mooncore.Endpoint.Socket.Clients`).

### State Structure

```elixir
%{
  "acme-corp" => %{           # group (dkey)
    "@alice" => [pid1],        # personal channel
    "main:default" => [pid1, pid2],  # scope channel
    "chat:default" => [pid1]   # joined channel
  },
  "other-corp" => %{
    "@bob" => [pid3],
    "main:default" => [pid3]
  }
}
```

### Querying Clients

```elixir
# All connected clients across all groups
Mooncore.Endpoint.Socket.Clients.list_all()

# All channels for a specific group
Mooncore.Endpoint.Socket.Clients.list_group("acme-corp")

# PIDs in a specific channel
Mooncore.Endpoint.Socket.Clients.list_members("acme-corp", "main:default")
```

### Client Pools

Configure multiple pools for different purposes:

```elixir
config :mooncore, pools: [:default, :admin, :stream]
```

Each pool runs its own `Clients` GenServer. Use different pools when you need isolated client registries. Pass the pool name as the last argument to client functions:

```elixir
Clients.add_member("group", "channel", self(), :admin)
Clients.list_all(:admin)
```

## Pushing Messages to Specific Clients

You can send messages directly to a client process if you have their PID:

```elixir
# From an action handler
send(req[:socket_pid], {:push, ["notification", %{message: "Hello!"}]})
```

The handler converts `{:push, data}` messages to WebSocket frames automatically.

## Error Handling

If a WebSocket message fails JSON decoding, the handler responds with:

```json
["socket_error", "json_decode_failed"]
```

Action errors within the pipeline are caught and returned as error maps — they don't crash the WebSocket connection.
