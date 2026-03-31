# Mooncore

A lightweight, action-based web framework for Elixir. A Phoenix alternative built around the action pattern.

## Core Concept

Every feature is an **action** — a named operation mapped to a module function. Actions are transport-agnostic: the same action works via HTTP, WebSocket, local Elixir call, or any other protocol.

```
               ┌─── HTTP (POST /run)
               │
Action.run/2 ◄─┼─── WebSocket
               │
               ├─── Local Elixir call
               │
               └─── Any protocol you add
```

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:mooncore, "~> 0.1.0"}
  ]
end
```

## Quick Start

### 1. Define your app

```elixir
defmodule MyApp.Roles do
  @roles ["admin", "manager", "user", "guest"]
  def list, do: @roles
end

defmodule MyApp.App do
  @behaviour Mooncore.App

  @impl true
  def list do
    %{
      "myapp" => %{
        key: "myapp",
        name: "My Application",
        roles: MyApp.Roles.list(),
        action_module: MyApp.Action
      }
    }
  end

  @impl true
  def info(app_name), do: Map.get(list(), app_name)
end
```

### 2. Define actions

> **Important:** `@actions` must be defined **before** `use Mooncore.Action`.
> The macro captures `@actions` at compile time.

```elixir
defmodule MyApp.Action do
  @actions %{
    "echo"        => {MyApp.Action.Echo, :echo, [], %{}},
    "task.create" => {MyApp.Action.Task, :create, ~w(user), %{}},
    "task.list"   => {MyApp.Action.Task, :list, ~w(user), %{}},
  }

  use Mooncore.Action
end

defmodule MyApp.Action.Echo do
  def echo(req), do: %{echo: req[:params]}
end

defmodule MyApp.Action.Task do
  def create(req) do
    # req[:params] is the full request body:
    # %{"action" => "task.create", "title" => "Buy milk", ...}
    title = req[:params]["title"]
    # ... your persistence logic ...
    # Publish to WebSocket clients:
    Mooncore.Endpoint.Socket.publish(req[:auth]["dkey"], {"task-created", %{title: title}})
    {:ok, %{title: title}}
  end

  def list(req) do
    # ... your query logic ...
    {:ok, []}
  end
end
```

### 3. Define your router

You own the router. Mooncore provides plugs and helpers, you compose them however you want:

```elixir
defmodule MyApp.Router do
  use Plug.Router

  plug Plug.Logger
  plug CORSPlug, origin: ["*"]
  plug Mooncore.Auth.Plug
  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, {:json, json_decoder: Jason}],
    length: 100_000_000
  plug :match
  plug :dispatch

  # Action endpoint — Mooncore handles dispatch + JSON response
  match "/run" do
    Mooncore.Endpoint.Http.handle(conn)
  end

  # Or handle it yourself for custom HTTP responses:
  match "/api" do
    result = Mooncore.Endpoint.Http.receive_action(conn)
    case result do
      %{error: "not found" <> _} ->
        conn |> put_resp_header("content-type", "application/json")
             |> send_resp(404, Jason.encode!(result))
      _ ->
        conn |> put_resp_header("content-type", "application/json")
             |> send_resp(200, Jason.encode!(Mooncore.Action.format_response(result)))
    end
  end

  # WebSocket
  get "/ws" do
    conn
    |> WebSockAdapter.upgrade(Mooncore.Endpoint.Socket.Handler, [conn: conn], timeout: 60_000)
    |> halt()
  end

  # Your custom routes
  get "/" do
    send_resp(conn, 200, "My App")
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
```

### 4. Configure

```elixir
# config/config.exs
config :mooncore,
  port: 4000,
  router: MyApp.Router,
  app_module: MyApp.App,
  jwt: [
    key: System.get_env("JWT_KEY"),
    issuer: "myapp"
  ],
  pools: [:default],
  before_action: [],
  after_action: []
```

### 5. Call actions from anywhere

```elixir
# From HTTP — handled by router
# POST /run {"action": "task.create", "title": "Test"}

# From WebSocket — handled by socket handler
# {"action": "task.create", "title": "Test", "rayid": "abc"}

# From Elixir code — no transport needed
MyApp.Action.run("task.create", %{
  params: %{"action" => "task.create", "title" => "Test"},
  auth: %{"roles" => ["user"]}
})

# Through the middleware pipeline
Mooncore.Action.execute("task.create", %{
  params: %{"action" => "task.create", "title" => "Test"},
  auth: %{"roles" => ["user"]}
})
```

### 6. Run

```bash
mix run --no-halt
```

`Mooncore.Application` starts the Bandit HTTP server automatically — you don't need to add anything to your own supervision tree.

## Middleware

Add before/after hooks to the action pipeline:

```elixir
defmodule MyApp.Middleware.DBLink do
  @behaviour Mooncore.Middleware

  @impl true
  def call(req) do
    db = MyApp.DB.resolve(req[:auth]["dkey"])
    Map.put(req, :db, db)
  end
end

defmodule MyApp.Middleware.AuditLog do
  @behaviour Mooncore.Middleware

  @impl true
  def call(response) do
    # Log the response, strip sensitive data, etc.
    if is_map(response), do: Map.delete(response, "password"), else: response
  end
end

# config/config.exs
config :mooncore,
  before_action: [MyApp.Middleware.DBLink],
  after_action: [MyApp.Middleware.AuditLog]
```

## WebSocket

Real-time pub/sub with channel support:

```elixir
# Publish to connected clients
Mooncore.Endpoint.Socket.publish("group_key", {"event", data})
Mooncore.Endpoint.Socket.publish("group_key", {"event", data}, ["main:default", "chat:lobby"])

# Clients connect to /ws and can:
# - Authenticate: ["jwt", "token_string"]
# - Join channels: ["join", "channel_name"] (requires "channel_<name>" role)
# - Leave channels: ["leave", "channel_name"]
# - Send actions: {"action": "...", "params": {...}, "rayid": "..."}
# - Ping: "ping" → "pong"
```

## MCP Server (AI Observability)

Query your running app's internals:

```elixir
Mooncore.MCP.Server.list_actions()   # All registered actions
Mooncore.MCP.Server.list_clients()   # Connected WebSocket clients
Mooncore.MCP.Server.list_apps()      # Registered apps
Mooncore.MCP.Server.server_info()    # Server configuration
```

## Action Definition Format

```elixir
"action.name" => {Module, :function, required_roles, request_modifications}
```

| Component | Description |
|-----------|-------------|
| `"action.name"` | Unique string identifier, dot-notation |
| `Module` | Handler module |
| `:function` | Function atom |
| `required_roles` | `[]` = public, `~w(user)` = requires "user" role |
| `request_modifications` | Map deep-merged into request before calling handler |

## License

MIT
