# AI Agent Guide

This guide is for AI coding agents (GitHub Copilot, Claude, Cursor, etc.) helping developers build applications with Mooncore. Read this before generating any code.

## Critical Rules

1. **Mooncore is NOT Phoenix.** No `Phoenix.Router`, no `Phoenix.Channel`, no `Phoenix.LiveView`, no `Ecto`, no `Repo`, no `Schema`, no `Changeset`, no `Controller`, no `View`. None of these exist here.
2. **`@actions` must be defined BEFORE `use Mooncore.Action`.** The macro captures it at compile time. If you put it after, actions silently won't work.
3. **Action handlers are plain functions.** They take a map, return a map. No base class, no macro, no special return wrapper.
4. **`req[:params]` is the full request body.** User data sits alongside `"action"` at the top level — there is no `params.body` or nested structure.
5. **Mooncore.Application starts the HTTP server automatically.** Never add Bandit or the HTTP server to your app's supervision tree.

## Project Scaffold

When creating a new Mooncore application, generate this structure:

```
my_app/
├── config/
│   └── config.exs
├── guides/
│   └── actions.md         # companion guide for the action set
├── lib/
│   ├── my_app.ex              # Application module
│   └── my_app/
│       ├── app.ex             # App registry (behaviour)
│       ├── action/
│       │   └── example.ex     # Action module + handlers
│       └── router.ex          # Plug.Router
├── test/
│   └── test_helper.exs
└── mix.exs
```

## File Templates

### mix.exs

```elixir
defmodule MyApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :my_app,
      version: "0.2.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MyApp.Application, []}
    ]
  end

  defp deps do
    [
      {:mooncore, "~> 0.2.0"}
    ]
  end
end
```

### config/config.exs

```elixir
import Config

config :mooncore,
  port: 4000,
  router: MyApp.Router,
  app_module: MyApp.App,
  mooncore_dev_tools: true,
  mcp_port: 4040
```

For authentication, add JWT config:

```elixir
config :mooncore,
  jwt: [
    key: System.get_env("JWT_PRIVATE_KEY"),
    issuer: "myapp"
  ]
```

### lib/my_app.ex (Application)

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = []
    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

Do NOT add Mooncore or Bandit to the children list. Mooncore starts its own HTTP server.

### lib/my_app/app.ex

```elixir
defmodule MyApp.App do
  @behaviour Mooncore.App

  @impl true
  def list do
    %{
      "myapp" => %{
        key: "myapp",
        name: "My Application",
        roles: ["admin", "user"],
        action_module: MyApp.Action.Main
      }
    }
  end

  @impl true
  def info(app_name), do: Map.get(list(), app_name)
end
```

### lib/my_app/action/main.ex

```elixir
defmodule MyApp.Action.Main do
  @actions %{
    "health"     => {__MODULE__, :health, [], %{}},
    "item.list"  => {__MODULE__, :list_items, ~w(user admin), %{}},
    "item.create" => {__MODULE__, :create_item, ~w(user admin), %{}}
  }

  use Mooncore.Action

  def health(_req), do: %{status: "ok"}

  def list_items(_req) do
    {:ok, %{items: []}}
  end

  def create_item(req) do
    name = req[:params]["name"]
    if name, do: {:ok, %{name: name}}, else: {:error, "name is required"}
  end
end
```

### lib/my_app/router.ex

```elixir
defmodule MyApp.Router do
  use Plug.Router

  plug Plug.Logger
  plug CORSPlug, origin: ["*"]
  plug Mooncore.Auth.Plug

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, {:json, json_decoder: Jason}],
    length: 10_000_000

  plug :match
  plug :dispatch

  match "/run" do
    Mooncore.Endpoint.Http.handle(conn)
  end

  get "/ws" do
    conn
    |> WebSockAdapter.upgrade(Mooncore.Endpoint.Socket.Handler, [conn: conn], timeout: 60_000)
    |> halt()
  end

  get "/" do
    send_resp(conn, 200, "MyApp is running")
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
```

### guides/actions.md

Create a companion guide for every new action or action module.

Keep the guide in `guides/` so the Dev Tools Guides screen can list it, open it, and run any Elixir code blocks inline.

Each guide should explain:

- what the action or action group does
- how to call it with `Mooncore.Action.execute/2`
- `curl` and WebSocket examples when relevant
- the expected inputs, roles, and middleware
- a short test or verification flow so the developer can see it working

Split guides by domain so each action group has its own file, such as `guides/users.md` or `guides/billing.md`.

Keep each code block short and independently runnable. Large multi-step snippets are harder to execute and debug safely in the Dev Tools inline runner.

## How Actions Work

### Defining Actions

Each action is a tuple in the `@actions` map:

```elixir
"action.name" => {HandlerModule, :function, required_roles, request_modifications}
```

- **`required_roles`**: `[]` = public (no auth). `~w(user admin)` = user needs at least one of these roles.
- **`request_modifications`**: map merged into the request before the handler runs. Useful for sharing a handler across actions with different config.

### Handler Functions

```elixir
def my_handler(req) do
  # Access params — the full request body (flat, not nested)
  action = req[:params]["action"]     # "item.create"
  name = req[:params]["name"]         # user-provided field

  # Access auth (nil if unauthenticated/public action)
  user = req[:auth]["user"]           # "alice"
  roles = req[:auth]["roles"]         # ["user", "admin"]
  dkey = req[:auth]["dkey"]           # "tenant-key"

  # Access middleware-injected keys
  db = req[:db]                       # from your DB middleware

  # Return any value
  %{result: "done"}
end
```

### Return Values

```elixir
%{items: [...]}                       # plain map — returned as-is
{:ok, %{item: item}}                  # unwrapped to %{item: item}
{:error, "not found"}                 # unwrapped to %{error: "not found"}
```

### Calling Actions

```bash
# HTTP
curl -X POST http://localhost:4000/run \
  -H "Content-Type: application/json" \
  -d '{"action": "item.create", "name": "Test"}'

# With auth
curl -X POST http://localhost:4000/run \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <jwt-token>" \
  -d '{"action": "item.create", "name": "Test"}'
```

```javascript
// WebSocket
ws.send(JSON.stringify({action: "item.create", name: "Test", rayid: "1"}))
// Response: ["response", {name: "Test"}, "1"]
```

```elixir
# Elixir (through middleware pipeline)
Mooncore.Action.execute("item.create", %{
  params: %{"action" => "item.create", "name" => "Test"},
  auth: %{"roles" => ["user"]}
})
```

## Organizing Larger Applications

### Multiple Action Modules

Split actions by domain. Each module is a separate entry in the app registry:

```elixir
# lib/my_app/app.ex
defmodule MyApp.App do
  @behaviour Mooncore.App

  @impl true
  def list do
    %{
      "users" => %{
        key: "users",
        name: "Users Service",
        roles: ["admin", "user"],
        action_module: MyApp.Action.Users
      },
      "billing" => %{
        key: "billing",
        name: "Billing Service",
        roles: ["admin", "billing_manager"],
        action_module: MyApp.Action.Billing
      }
    }
  end

  @impl true
  def info(app_name), do: Map.get(list(), app_name)
end
```

```elixir
# lib/my_app/action/users.ex
defmodule MyApp.Action.Users do
  @actions %{
    "user.create"  => {MyApp.Action.Users.Handler, :create, ~w(admin), %{}},
    "user.list"    => {MyApp.Action.Users.Handler, :list, ~w(admin user), %{}},
    "user.profile" => {MyApp.Action.Users.Handler, :profile, ~w(user), %{}}
  }

  use Mooncore.Action
end
```

### Middleware

Add request enrichment or response processing:

```elixir
defmodule MyApp.Middleware.DB do
  @behaviour Mooncore.Middleware

  @impl true
  def call(req) do
    db = MyApp.DB.connect(req[:auth]["dkey"])
    Map.put(req, :db, db)
  end
end
```

```elixir
# config/config.exs
config :mooncore,
  before_action: [MyApp.Middleware.DB],
  after_action: []
```

### WebSocket Publishing

Broadcast events from action handlers:

```elixir
def create_item(req) do
  item = %{name: req[:params]["name"]}
  # Publish to all clients in the same tenant group
  Mooncore.Endpoint.Socket.publish(req[:auth]["dkey"], {"item_created", item})
  {:ok, item}
end
```

## Common Patterns

### ETS for In-Memory State

Mooncore doesn't include a database layer. For simple apps, use ETS:

```elixir
# In Application.start/2
:ets.new(:my_table, [:named_table, :public, :set])

# In handlers
:ets.insert(:my_table, {id, data})
:ets.lookup(:my_table, id)
```

### External Databases

Add any database library as a dependency. Mooncore has no opinion here — use Ecto, ArangoDB client, Redis, or anything else. Inject the connection via middleware.

### Multi-Tenant Isolation

Use `dkey` (domain key) from auth claims for tenant isolation. WebSocket channels, publishing, and client registries are all scoped by `dkey` automatically.

### File Serving / Custom Pages

Serve HTML directly from the router:

```elixir
get "/dashboard" do
  conn
  |> put_resp_content_type("text/html")
  |> send_resp(200, MyApp.Page.render())
end
```

For static HTML compiled into the module:

```elixir
defmodule MyApp.Page do
  @external_resource "lib/my_app/page.html"
  @page_html File.read!("lib/my_app/page.html")

  def render, do: @page_html
end
```

## What NOT to Do

| Don't                                                 | Do Instead                                                 |
| ----------------------------------------------------- | ---------------------------------------------------------- |
| Add `Bandit.child_spec(...)` to your supervision tree | Mooncore starts the server automatically                   |
| Use `Phoenix.Router` or `Phoenix.Controller`          | Use `Plug.Router` with `Mooncore.Endpoint.Http.handle/1`   |
| Use `Ecto.Schema` / `Ecto.Changeset`                  | Use plain maps; add any DB library you want                |
| Put `use Mooncore.Action` before `@actions`           | Always define `@actions` first, then `use Mooncore.Action` |
| Nest params like `req[:params]["body"]["name"]`       | Params are flat: `req[:params]["name"]`                    |
| Create controllers or views                           | Write action handler functions that return maps            |
| Use `Phoenix.PubSub`                                  | Use `Mooncore.Endpoint.Socket.publish/3`                   |
| Return `{:noreply, socket}` style tuples              | Return plain maps or `{:ok, data}` / `{:error, reason}`    |

## Dev Tools

When `mooncore_dev_tools: true` is configured and `MOONCORE_DEV_SECRET` is set:
- Dev dashboard at `http://localhost:4040/` — VM metrics, action runner, console, file browser
- MCP server at `http://localhost:4040/mcp` — connect VS Code or other AI tools
- All action executions are logged and visible in the dashboard

Add to `.vscode/mcp.json` to connect this framework's MCP server:

```json
{
  "servers": {
    "mooncore": {
      "type": "http",
      "url": "http://localhost:4040/mcp"
    }
  }
}
```

## Running the Application

```bash
mix deps.get
mix run --no-halt
```

The server starts on the configured port (default 4000). Dev dashboard on port 4040 if `mooncore_dev_tools: true` is set and `MOONCORE_DEV_SECRET` is set.
