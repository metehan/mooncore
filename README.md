<p align="center">
  <img src="guides/mooncore.png" alt="Mooncore" width="120" />
</p>

# Mooncore

A lightweight, action-based API framework for Elixir.

## What is Mooncore

Mooncore is a minimal Elixir framework for building APIs. It gives you everything you need — HTTP, WebSocket, authentication, middleware, and an MCP server for AI agents — with zero boilerplate and no heavyweight dependencies.

- **Minimal and focused.** No ORM, no templating, no asset pipeline. Just the tools you need for APIs.
- **Multi-transport out of the box.** HTTP and WebSocket work from day one with the same application logic.
- **Built-in auth.** JWT authentication (RS256) with role-based access control, ready to use.
- **AI-ready.** Ships with an MCP server so AI agents can discover, call, and test your API directly.
- **Functional and predictable.** Every operation is a function: parameters in, result out. No hidden state, no magic.

Mooncore runs on [Bandit](https://github.com/mtrudel/bandit) and [Plug](https://github.com/elixir-plug/plug), so you get the performance and reliability of the BEAM with a surface area small enough to read in an afternoon.

### Actions

At its core, Mooncore uses a single concept to model your entire API: **actions**. Every feature is a named function call — not an HTTP endpoint.

#### Why not REST?
REST was designed for documents — CRUD operations on URL-addressable resources. It works, but it forces you to think in terms of HTTP: which verb, which URL path, which status code, how to nest resources, how to handle batch operations that don't fit the resource model. Actions let you skip all of that:

```
REST                              Mooncore
────                              ────────
GET    /api/tasks                 "task.list"
POST   /api/tasks                 "task.create"
PUT    /api/tasks/:id             "task.update"
DELETE /api/tasks/:id             "task.delete"
POST   /api/tasks/:id/assign      "task.assign"
POST   /api/tasks/batch-archive   "task.batch_archive"
GET    /api/reports/weekly?...     "report.weekly"
```

No routing tables, no path params, no verb selection, no "is this a PUT or PATCH" debates. Just action names and parameters.

### Transport Independence

Actions don't know how they were called. The same `"task.create"` works across every transport without modification:

```
               ┌─── HTTP POST /run
               │
               ├─── WebSocket message
               │
Action.run/2 ◄─┼─── Elixir function call
               │
               ├─── MCP tool call (AI agents)
               │
               ├─── Protobuf / gRPC adapter
               │
               ├─── Message queue consumer
               │
               └─── Cron scheduler
```

Write the logic once, plug in transports. Need a NATS consumer that triggers `"order.process"`? It's one adapter that calls `Action.execute/2` — your handler doesn't change.

### AI-Native Development

Actions are pure functions: a name, a parameter map, a result. This is the ideal interface for AI-assisted development — an agent can generate a handler, call it through the built-in MCP server, inspect the result, and iterate. No HTTP client setup, no URL construction, no status code interpretation. Just `{"action": "task.create", "title": "Buy milk"}`.

Because Mooncore includes an MCP server out of the box, AI agents connect directly to the running application. They discover available actions, execute them, read logs, and evaluate code — all through the same action interface your frontend uses. The functional style (map in, map out) means agents produce correct code faster with fewer tokens, since there's no framework boilerplate or object hierarchy to reason about.

### Clean Separation

Because actions are transport-agnostic, your application logic has zero coupling to HTTP, WebSocket, or any delivery mechanism. This means:

- **UI logic stays in the UI.** Your backend is a flat list of operations, not a REST hierarchy that mirrors your page structure.
- **Testing is trivial.** Call the action function directly with a map. No HTTP client, no router, no connection struct.
- **New protocols are adapters, not rewrites.** Add protobuf, GraphQL, message queues, or schedulers without touching business logic.

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

| Component               | Description                                         |
| ----------------------- | --------------------------------------------------- |
| `"action.name"`         | Unique string identifier, dot-notation              |
| `Module`                | Handler module                                      |
| `:function`             | Function atom                                       |
| `required_roles`        | `[]` = public, `~w(user)` = requires "user" role    |
| `request_modifications` | Map deep-merged into request before calling handler |

## For AI Agents

If you are an AI coding agent, read [`guides/skills.md`](guides/skills.md) before generating Mooncore code. It contains scaffolding templates, critical rules and common patterns.

## License

MIT
