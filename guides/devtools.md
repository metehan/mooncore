# Dev Tools

Mooncore includes a built-in development dashboard and MCP (Model Context Protocol) server for observability. Everything is gated behind devmode — nothing is exposed when devmode is off.

## Enabling Dev Mode

```elixir
# config/dev.exs
config :mooncore, devmode: true
```

```elixir
# config/prod.exs — never enable in production
config :mooncore, devmode: false
```

When devmode is enabled:
- The Watcher GenServer starts (in-memory log collector)
- The MCP Server functions become available
- The Dev Dashboard serves at `/mooncore`

When devmode is off:
- Watcher doesn't start
- All MCP Server functions return errors
- Dev Dashboard returns 404

## Dev Dashboard

Mount the dashboard in your router:

```elixir
forward "/mooncore", to: Mooncore.Dev.Plug
```

The dashboard is a single-page app built with Bootstrap 5 and Preact (loaded from CDN). It provides five tabs:

### Actions Tab

Lists all registered actions across all apps with their handler modules, required roles, and public/protected status.

### Runner Tab

Execute actions directly from the browser. Enter an action name, JSON parameters, and optional auth — see the result in real-time.

### Logs Tab

View lifecycle logs collected by the Watcher. Filter by tag, auto-refresh, and see elapsed times for each action phase.

Trigger lifecycle logging by adding `"mooncore_log": true` to any action's parameters:

```bash
curl -X POST http://localhost:4000/run \
  -H "Content-Type: application/json" \
  -d '{"action": "task.create", "title": "Test", "mooncore_log": true}'
```

### Console Tab

An IEx-like REPL in the browser. Evaluate Elixir code against the running application:

```elixir
Mooncore.App.list()
Mooncore.Endpoint.Socket.Clients.list_all()
:ets.all() |> length()
```

Results are displayed with `inspect/1` formatting.

### Config Tab

View the current Mooncore configuration (sanitized — no secrets).

## MCP Server

The MCP Server exposes framework internals for AI tools, IDE integrations, or custom tooling. All functions require devmode.

### Resources (Read-Only)

```elixir
# List all registered actions
Mooncore.MCP.Server.list_actions()
# [%{app: "myapp", action: "task.create", handler: "MyApp.Action.Task.create", roles: ["user"], public: false}, ...]

# List connected WebSocket clients
Mooncore.MCP.Server.list_clients()
# [%{group: "acme", channels: [%{channel: "@alice", count: 1}], total: 1}]

# List registered apps
Mooncore.MCP.Server.list_apps()
# [%{key: "myapp", name: "My Application", roles: [...], action_module: "MyApp.Action"}]

# Get server configuration
Mooncore.MCP.Server.server_info()
# %{port: 4000, router: "MyApp.Router", devmode: true, ...}
```

### Tools

```elixir
# Execute an action
Mooncore.MCP.Server.run_action("task.list", %{}, nil)

# Evaluate Elixir code
Mooncore.MCP.Server.eval_code("1 + 1")
# %{result: "2"}

# Subscribe to log stream
Mooncore.MCP.Server.add_watcher_session(:lifecycle)

# Read collected logs
Mooncore.MCP.Server.read_logs(%{"tag" => "lifecycle"})
Mooncore.MCP.Server.read_logs(%{"since" => 42})

# Clear logs
Mooncore.MCP.Server.clear_logs()
```

### JSON API

The Dev Plug exposes a JSON API for all MCP operations:

| Method | Path | Description |
|--------|------|-------------|
| POST | `/mooncore/api/mcp` | Generic MCP request (resource or tool) |
| POST | `/mooncore/api/eval` | Evaluate Elixir code |
| POST | `/mooncore/api/action` | Execute an action |
| GET | `/mooncore/api/logs` | Read logs (query params: `tag`, `since`) |
| GET | `/mooncore/api/actions` | List all actions |
| GET | `/mooncore/api/config` | Get server config |
| GET | `/mooncore/api/apps` | List apps |

#### MCP Request Format

```bash
# Get a resource
curl -X POST http://localhost:4000/mooncore/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"resource": "actions"}'

# Run a tool
curl -X POST http://localhost:4000/mooncore/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"tool": "run_action", "action": "echo", "params": {"message": "hello"}}'

# Evaluate code
curl -X POST http://localhost:4000/mooncore/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"tool": "eval", "code": "Enum.sum(1..100)"}'
```

## Watcher

The Watcher is a GenServer that collects logs in a ring buffer (max 1000 entries by default). It only runs when devmode is enabled.

### Logging Events

From anywhere in your application:

```elixir
# Log with a tag
Mooncore.MCP.Watcher.log(:custom, %{message: "Something happened", user: "alice"})

# Log with different tags
Mooncore.MCP.Watcher.log(:db, %{query: "FOR t IN tasks RETURN t", time_ms: 12})
Mooncore.MCP.Watcher.log(:auth, %{event: "login", user: "alice"})
Mooncore.MCP.Watcher.log(:error, %{action: "task.create", reason: "validation failed"})
```

The `:lifecycle` tag is used automatically by the action pipeline when `mooncore_log: true`.

### Reading Logs

```elixir
# All logs (newest first)
Mooncore.MCP.Watcher.read()

# Filtered by tag
Mooncore.MCP.Watcher.read(:lifecycle)
Mooncore.MCP.Watcher.read(:custom)

# Since a specific entry ID (for polling)
Mooncore.MCP.Watcher.read_since(last_seen_id)
```

### Real-Time Watchers

Subscribe a process to receive logs as they happen:

```elixir
# Watch all logs
Mooncore.MCP.Watcher.add_watcher(self())

# Watch only lifecycle logs
Mooncore.MCP.Watcher.add_watcher(self(), :lifecycle)

# Receive logs
receive do
  {:mooncore_log, tag, entry} ->
    IO.inspect({tag, entry})
end

# Stop watching
Mooncore.MCP.Watcher.remove_watcher(self())
```

### Log Entry Format

Each log entry is a map:

```elixir
%{
  id: 1,                          # unique, incrementing integer
  tag: :lifecycle,                 # the tag atom
  data: %{action: "task.create"},  # your data
  ts: 1711827600000                # timestamp (milliseconds)
}
```

## Security Notes

- **Never enable devmode in production.** The eval tool and action runner provide full access to the running system.
- The Dev Plug returns 404 when devmode is off. The MCP Server functions throw errors when devmode is off. Both layers of protection ensure nothing leaks.
- The console evaluates real Elixir code — treat it like an IEx session with full system access.
- Server config is sanitized (values are inspected as strings), but sensitive data could still be visible through eval or action execution.
