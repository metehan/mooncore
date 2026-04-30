# WebSockets

Mooncore treats WebSockets as a first-class transport. The same actions that work over HTTP work over WebSocket — no duplication required. On top of that, the framework adds channels, pub/sub broadcasting, binary protocol support, and a client registry.

## Setup

Add the WebSocket upgrade route to your router:

```elixir
defmodule MyApp.Router do
  use Plug.Router

  plug Mooncore.Auth.Plug
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

`Mooncore.Auth.Plug` runs before the upgrade, so any JWT in the `Authorization` header is already decoded by the time the WebSocket handler initializes.

## Connection Lifecycle

### 1. Connect

The client opens a WebSocket connection to `/ws`.

- If a valid JWT was present in the HTTP upgrade request, the connection is authenticated immediately and the client is registered in their personal and scope channels.
- If no JWT was provided, the connection is registered as an anonymous pending connection (group `_anon`, channel `ws:pending`) until the client authenticates over the socket.

### 2. Authenticate Over the Socket

If the client didn't send a JWT during the HTTP upgrade, send it after connecting:

```json
["jwt", "eyJhbGciOiJSUzI1NiIs..."]
```

**Success response:**
```json
["jwt", {"user": "alice", "app": "myapp", "roles": ["user"], "dkey": "acme-corp", "scope": "default"}]
```

**Failure response:**
```json
["jwt", "jwt_failed"]
```

On success the client is automatically subscribed to:
- `@alice` — personal channel
- `main:default` — scope channel (based on the `scope` claim in the JWT)

### 3. Run Actions

Any JSON object with an `"action"` key is dispatched through the full action pipeline (same as HTTP, including middleware):

```json
{"action": "task.create", "title": "My Task", "rayid": "req-1"}
```

**Response pushed back to the same client:**
```json
["response", {"ok": true, "task": {"id": "abc", "title": "My Task"}}, "req-1"]
```

The `rayid` is a client-generated correlation ID — echo it with every request and the server will echo it back in the response so you can match async responses to requests.

The action handler receives the same request map as HTTP actions, with these additions:
```elixir
%{
  auth: %{"user" => "alice", ...},
  params: %{"action" => "task.create", "title" => "My Task", "rayid" => "req-1"},
  source: "ws",
  socket_pid: pid,     # the handler process PID
  rayid: "req-1"
}
```

### 4. Disconnect

Send `"quit"` or just close the connection. The handler automatically removes the client from all channel subscriptions in the registry.

## Control Messages

These are handled directly by the socket handler — they bypass the action pipeline:

| Client sends         | Server responds                                | Description                      |
| -------------------- | ---------------------------------------------- | -------------------------------- |
| `"ping"`             | `"pong"`                                       | Keep-alive check                 |
| `"time"`             | `["server_time", 1711827600000]`               | Server timestamp in milliseconds |
| `"channel_list"`     | `["channel_list", ["@alice", "main:default"]]` | List current subscriptions       |
| `"quit"`             | _(connection closed)_                          | Graceful disconnect              |
| `["jwt", token]`     | `["jwt", auth]` or `["jwt", "jwt_failed"]`     | Authenticate                     |
| `["join", channel]`  | `["channel_list", [...]]`                      | Subscribe to a channel           |
| `["leave", channel]` | `["channel_list", [...]]`                      | Unsubscribe from a channel       |

## Channels

Channels are named subscriptions. A message published to a channel is broadcast to every client currently subscribed to it.

### Auto-subscribed on auth

On successful authentication, the client is automatically subscribed to their **personal channel** only:

| Channel       | Example  | Who                             |
| ------------- | -------- | ------------------------------- |
| `@{username}` | `@alice` | Only this user (personal inbox) |

The scope/broadcast channel (`main:{scope}`) is **not** auto-joined. Clients must explicitly join it. This prevents all 100k connections from landing in one massive channel by default.

### Joining Channels

To join the scope channel (any authenticated user may):

```json
["join", "main"]
```

To join a custom channel (requires role `channel_{name}`):

```json
["join", "chat"]
```

The user needs role `channel_chat` to join `chat`. The server subscribes them to `chat:{scope}` and responds with the updated list:

```json
["channel_list", ["@alice", "main:default", "chat:default"]]
```

If the join is not permitted, the server responds with the current channel list unchanged — no error.

### Leaving Channels

```json
["leave", "main"]
["leave", "chat"]
```

Response:
```json
["channel_list", ["@alice"]]
```

### Channel Scoping & Tenant Isolation

All channels are qualified by the client's `dkey` (domain key from the JWT). When you publish to a channel, only clients sharing the same `dkey` receive the message. Two different tenants with the same channel name never overlap.

```
Client A: dkey=acme, channels=["@alice", "main:default"]
Client B: dkey=globex, channels=["@alice", "main:default"]

publish("acme", ..., ["main:default"])  → only Client A receives it
```

## Publishing Messages (Server → Clients)

From anywhere in your application code, broadcast to connected clients:

```elixir
# Publish to the default channel of a group
Mooncore.Endpoint.Socket.publish("acme-corp", {"task_created", %{id: "123", title: "New Task"}})

# Publish to specific channels
Mooncore.Endpoint.Socket.publish("acme-corp", {"notification", %{text: "Hello"}}, ["main:default", "main:branch1"])

# Publish to a specific user's personal channel
Mooncore.Endpoint.Socket.publish("acme-corp", {"dm", %{from: "bob", text: "Hi!"}}, ["@alice"])

# Publish to a custom channel
Mooncore.Endpoint.Socket.publish("acme-corp", {"chat_message", %{text: "Hey"}}, ["chat:default"])
```

Arguments:
1. `group` (string) — the `dkey` that identifies which tenant's clients to target
2. `{event_name, payload}` — a tuple with the event name and any term as payload; maps must not contain a `"password"` key (stripped automatically)
3. `channels` (list) — defaults to `["main:default"]`

Clients receive published messages as:
```json
["task_created", {"id": "123", "title": "New Task"}]
```

### Sending Directly to a PID

From an action handler, you can also push a message directly to the calling client's socket:

```elixir
def my_action(req) do
  send(req[:socket_pid], {:push, ["notification", %{message: "Processing..."}]})
  %{ok: true}
end
```

## Binary Protocol

The handler supports a binary protocol for sending files or other binary data alongside JSON metadata.

### Wire Format

```
[2 bytes: little-endian uint16 metadata_length]
[metadata_length bytes: UTF-8 JSON metadata]
[remaining bytes: raw binary payload]
```

### Sending Binary (JavaScript client)

```javascript
const metadata = JSON.stringify({
  action: "file.upload",
  filename: "photo.jpg",
  rayid: "upload-1"
});

const metaBytes = new TextEncoder().encode(metadata);
const header = new Uint8Array(new Uint16Array([metaBytes.length]).buffer); // little-endian

const frame = new Uint8Array(header.byteLength + metaBytes.byteLength + fileBytes.byteLength);
frame.set(header, 0);
frame.set(metaBytes, header.byteLength);
frame.set(new Uint8Array(fileBytes), header.byteLength + metaBytes.byteLength);

ws.send(frame);
```

### Receiving Binary in an Action Handler

The binary payload is available as `params["bind"]` — everything after the metadata:

```elixir
defmodule MyApp.Action.File do
  def upload(req) do
    binary_data = req[:params]["bind"]
    filename    = req[:params]["filename"]

    File.write!("/uploads/#{filename}", binary_data)
    %{ok: true, filename: filename, size: byte_size(binary_data)}
  end
end
```

## Client Registry

Mooncore tracks every connected WebSocket client using a per-pool GenServer (`Mooncore.Endpoint.Socket.Clients`).

### State Structure

```elixir
%{
  "_anon" => %{
    "ws:pending" => [pid_unauthenticated]  # unauthenticated connections
  },
  "acme-corp" => %{
    "@alice" => [pid1],                     # personal channel
    "main:default" => [pid1, pid2],         # scope channel
    "chat:default" => [pid1]                # joined custom channel
  }
}
```

Unauthenticated connections live under the `_anon` group until they authenticate (or disconnect). On authentication they are moved to the correct group. On disconnect, all entries are cleaned up automatically.

### Querying the Registry

```elixir
alias Mooncore.Endpoint.Socket.Clients

# All connected clients in the default pool
Clients.list_all()

# All channels for a specific group (tenant)
Clients.list_group("acme-corp")

# PIDs subscribed to a specific channel
Clients.list_members("acme-corp", "main:default")
Clients.list_members("acme-corp", "@alice")
```

### Multiple Pools

Configure multiple isolated registries for different purposes:

```elixir
config :mooncore, pools: [:default, :admin, :stream]
```

Each pool is its own GenServer. Pass the pool name as the last argument:

```elixir
Clients.list_all(:admin)
Clients.add_member("group", "channel", self(), :stream)
```

The WebSocket handler always registers into the `:default` pool. To use a custom pool, you'd build your own handler or add members programmatically.

## Error Handling

If the client sends a message that isn't valid JSON, the server responds:

```json
["socket_error", "json_decode_failed"]
```

Action errors are caught and returned as error maps — they don't crash the WebSocket connection or disconnect the client.

## Observability (Dev Tools)

When `mooncore_dev_tools: true` is configured, every incoming and outgoing socket message is logged with:
- Direction (`in` / `publish`)
- User and dkey
- Active channels at the time
- Full payload

The **Sockets** tab in the dev dashboard shows these logs in real time with filters by direction, user, channel, and limit.

MCP clients can also:
- Call `read_socket_logs` to query logs with the same filters
- Call `list_clients` to see all connected clients across all pools
- Call `publish_socket` to send a message to connected clients from an AI agent
