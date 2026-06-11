# Getting Started

This guide walks you through creating a new Mooncore application from scratch.

## Installation

Add Mooncore to your dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:mooncore, "~> 0.2.0"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Project Structure

Mooncore doesn't enforce a project structure. Here's a minimal setup that works well:

```
my_app/
├── lib/
│   ├── my_app/
│   │   ├── action.ex        # Action registry
│   │   ├── action/
│   │   │   └── task.ex       # Action handlers
│   │   ├── app.ex            # App registry
│   │   └── router.ex         # HTTP router
│   └── my_app.ex             # Application module
├── config/
│   └── config.exs
├── test/
└── mix.exs
```

## Configuration

Configure Mooncore in `config/config.exs`:

```elixir
import Config

config :mooncore,
  port: 4000,
  router: MyApp.Router,
  app_module: MyApp.App,
  jwt: [
    key: System.get_env("JWT_PRIVATE_KEY"),
    issuer: "myapp"
  ],
  pools: [:default],
  before_action: [],
  after_action: []
```

### Configuration Keys

| Key                     | Type    | Description                                                                                 |
| ----------------------- | ------- | ------------------------------------------------------------------------------------------- |
| `port`                  | integer | HTTP listening port (default: 4000)                                                         |
| `router`                | module  | Your Plug.Router module                                                                     |
| `app_module`            | module  | Your App registry module                                                                    |
| `jwt`                   | keyword | `[key: "RSA private key PEM", issuer: "name"]`                                              |
| `pools`                 | list    | Named client pool atoms (default: `[:default]`)                                             |
| `before_action`         | list    | Middleware modules run before actions                                                       |
| `after_action`          | list    | Middleware modules run after actions                                                        |
| `mooncore_dev_tools`    | boolean | Enables dev dashboard and MCP server (also requires `MOONCORE_DEV_SECRET` env var)          |
| `dev_tools_allowed_ips` | list    | IP allowlist for dev tools (e.g. `["127.0.0.1", "10.0.0.0/8"]`). If unset, all IPs allowed. |
| `oauth_access_token_ttl_seconds` | integer | MCP OAuth access token lifetime in seconds (default: 1,209,600 / 14 days). |

## Step 1: Define Your App

The app module tells Mooncore which action modules exist and what roles they support:

```elixir
defmodule MyApp.App do
  @behaviour Mooncore.App

  @impl true
  def list do
    %{
      "myapp" => %{
        key: "myapp",
        name: "My Application",
        roles: ["admin", "user", "editor"],
        action_module: MyApp.Action
      }
    }
  end

  @impl true
  def info(app_name), do: Map.get(list(), app_name)
end
```

## Step 2: Define Your Actions

Create an action module. **Define `@actions` before `use Mooncore.Action`** — the macro captures the attribute at compile time:

```elixir
defmodule MyApp.Action do
  @actions %{
    "echo"        => {MyApp.Action.Echo, :echo, [], %{}},
    "task.create" => {MyApp.Action.Task, :create, ~w(user admin), %{}},
    "task.list"   => {MyApp.Action.Task, :list, ~w(user admin), %{}},
  }

  use Mooncore.Action
end
```

Each action entry is:

```elixir
"action.name" => {HandlerModule, :function, required_roles, request_modifications}
```

- `required_roles` — `[]` means public (no auth needed). Otherwise, user must have at least one of these roles.
- `request_modifications` — a map that gets deep-merged into the request before calling the handler.

## Step 3: Write Action Handlers

Action handlers are plain functions that receive a request map and return a result.

`req[:params]` is the **entire request body** — user data sits alongside the `"action"` key:

```elixir
# Client sends: POST /run {"action": "task.create", "title": "Buy milk"}
# Handler receives: req[:params] = %{"action" => "task.create", "title" => "Buy milk"}
```

```elixir
defmodule MyApp.Action.Echo do
  def echo(req) do
    %{echo: req[:params]}
  end
end

defmodule MyApp.Action.Task do
  def create(req) do
    title = req[:params]["title"]
    # ... create the task in your database
    %{ok: true, task: %{title: title, id: "new-id"}}
  end

  def list(req) do
    # ... fetch tasks from your database
    %{tasks: []}
  end
end
```

That's it — no base classes, no macros, no special return types. A function that takes a map and returns a map.

## Step 4: Create Your Router

Write a standard Plug.Router:

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

  # Action endpoint — POST any action here
  match "/run" do
    Mooncore.Endpoint.Http.handle(conn)
  end

  # WebSocket endpoint
  get "/ws" do
    conn
    |> WebSockAdapter.upgrade(
      Mooncore.Endpoint.Socket.Handler,
      [conn: conn],
      timeout: 60_000
    )
    |> halt()
  end

  # Your own routes
  get "/" do
    send_resp(conn, 200, "My App is running")
  end

  get "/health" do
    send_resp(conn, 200, "ok")
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
```

## Step 5: Run It

Start your application:

```bash
mix run --no-halt
```

Or in IEx:

```bash
iex -S mix
```

`Mooncore.Application` starts the Bandit HTTP server automatically on the configured port — you don't need to add anything to your own supervision tree.

Test it:

```bash
# Public action (no auth required)
curl -X POST http://localhost:4000/run \
  -H "Content-Type: application/json" \
  -d '{"action": "echo", "message": "hello"}'

# Response: {"echo": {"action": "echo", "message": "hello"}}
```

## Step 6: Generate a JWT

For actions that require roles, you need a JWT token. In IEx:

```elixir
{:ok, token} = Mooncore.Auth.Token.new_token(%{
  "user" => "alice",
  "app" => "myapp",
  "tenant" => "my-domain",
  "scope" => "default",
  "roles" => Mooncore.Util.Base58.from_integer(
    Mooncore.Util.Deflist.to_integer(["admin", "user", "editor"], ["user"])
  )
})
```

Then use it:

```bash
curl -X POST http://localhost:4000/run \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d '{"action": "task.list"}'
```

## Next Steps

- [Actions Guide](actions.md) — deep dive into the action system
- [Authentication Guide](authentication.md) — JWT, roles, and the Base58 bitmask encoding
- [WebSocket Guide](websockets.md) — channels, pub/sub, and binary protocol
- [Middleware Guide](middleware.md) — before/after hooks for cross-cutting concerns
- [Dev Tools Guide](devtools.md) — development dashboard and MCP server
