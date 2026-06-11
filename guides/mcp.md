# MCP Server

Mooncore includes a built-in [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) server that exposes your application's internals to AI tools, IDE extensions, and custom integrations. It implements the **Streamable HTTP** transport with JSON-RPC 2.0.

> **Security:** The MCP server provides full access to action execution, code evaluation, and log inspection. Never enable `mooncore_dev_tools` in production.

## Setup

Enable `mooncore_dev_tools` in your config:

```elixir
config :mooncore,
  mooncore_dev_tools: true,
  mcp_port: 4040   # default
```

Also set `MOONCORE_DEV_SECRET` before starting the app:

```bash
export MOONCORE_DEV_SECRET=your-secret-here
```

The MCP endpoint is available at `http://localhost:4040/mcp` when the server is running.

## Protocol

Mooncore implements the MCP specification (protocol version `2025-03-26`) over HTTP POST with JSON-RPC 2.0:

```
POST http://localhost:4040/mcp
Content-Type: application/json

{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}
```

Supported JSON-RPC methods:

| Method           | Description                                                     |
| ---------------- | --------------------------------------------------------------- |
| `initialize`     | Handshake — returns protocol version, capabilities, server info |
| `ping`           | Keepalive check                                                 |
| `tools/list`     | List all available tools with input schemas                     |
| `tools/call`     | Call a tool by name with arguments                              |
| `resources/list` | List all available resources with URIs                          |
| `resources/read` | Read a resource by URI                                          |

Batch requests (JSON array) are supported. Notifications (requests without `id`) return HTTP 202.

### Initialize Response

```json
{
  "protocolVersion": "2025-03-26",
  "capabilities": { "tools": {}, "resources": {} },
  "serverInfo": { "name": "mooncore", "version": "0.2.0" }
}
```

## Tools

Tools are callable operations that can modify state or execute code.

### run_action

Execute a Mooncore action through the full pipeline (role checking, middleware, logging).

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "run_action",
    "arguments": {
      "action": "task.create",
      "params": {"title": "New task"},
      "auth": {"roles": ["user"], "user": "alice"}
    }
  }
}
```

| Argument | Type   | Required | Description                                  |
| -------- | ------ | -------- | -------------------------------------------- |
| `action` | string | yes      | Action name (e.g. `task.create`)             |
| `params` | object | no       | Parameters to pass to the action             |
| `auth`   | object | no       | Auth context (roles, user, app, tenant, scope) |

### eval

Evaluate Elixir code in the running application. Equivalent to IEx.

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "eval",
    "arguments": {
      "code": "Enum.map(1..5, & &1 * 2)"
    }
  }
}
```

| Argument | Type   | Required | Description             |
| -------- | ------ | -------- | ----------------------- |
| `code`   | string | yes      | Elixir code to evaluate |

Returns the inspected result or an error message.

### read_logs

Read collected logs from the Watcher ring buffer.

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "read_logs",
    "arguments": {
      "tag": "action",
      "since_id": 42
    }
  }
}
```

| Argument   | Type    | Required | Description                                              |
| ---------- | ------- | -------- | -------------------------------------------------------- |
| `tag`      | string  | no       | Filter logs by tag (e.g. `action`, `lifecycle`, `error`) |
| `since_id` | integer | no       | Only return logs with ID greater than this value         |

### clear_logs

Clear all collected logs in the Watcher buffer.

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {
    "name": "clear_logs",
    "arguments": {}
  }
}
```

No arguments required.

## Resources

Resources are read-only data that provide context about the running application.

### mooncore://actions

All registered actions across all apps.

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "resources/read",
  "params": { "uri": "mooncore://actions" }
}
```

Returns:

```json
[
  {
    "app": "myapp",
    "action": "task.create",
    "handler": "MyApp.Action.Task.create",
    "roles": ["user"],
    "public": false
  }
]
```

### mooncore://apps

Registered app configurations.

```json
[
  {
    "key": "myapp",
    "name": "My Application",
    "roles": ["admin", "user"],
    "action_module": "MyApp.Action"
  }
]
```

### mooncore://clients

Connected WebSocket client counts per group and channel.

```json
[
  {
    "group": "acme",
    "channels": [
      {"channel": "@alice", "count": 1},
      {"channel": "#general", "count": 3}
    ],
    "total": 4
  }
]
```

### mooncore://config

Current server configuration (sanitized).

```json
{
  "port": 4000,
  "pools": ["default"],
  "router": "MyApp.Router",
  "app_module": "MyApp.App",
  "watcher_count": 0,
  "log_count": 15
}
```

## VS Code Integration

Connect VS Code (GitHub Copilot agent mode) to your running Mooncore app.

Add to `.vscode/mcp.json` in your project:

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

Once connected, the AI agent can:
- **Run actions** — test your API by calling actions with parameters
- **Read logs** — inspect what happened during action execution
- **Evaluate code** — run Elixir expressions in your live app
- **Browse resources** — see all actions, apps, clients, and config

OAuth access tokens are valid for 14 days by default. Configure a different positive
lifetime in seconds when needed:

```elixir
Application.put_env(:mooncore, :oauth_access_token_ttl_seconds, 1_209_600)
```

Changing `MOONCORE_DEV_SECRET` immediately invalidates previously issued tokens.

### Example AI Workflow

The agent reads `mooncore://actions` to understand your API, then uses `run_action` to test an endpoint, reads logs to debug issues, and uses `eval` to inspect application state.

## JSON API

In addition to the standard MCP protocol, the dev server exposes a simpler JSON API on the same port for direct HTTP access:

| Method | Path             | Description                                     |
| ------ | ---------------- | ----------------------------------------------- |
| POST   | `/api/mcp`       | Generic MCP request (resource or tool)          |
| POST   | `/api/eval`      | Evaluate Elixir code                            |
| POST   | `/api/action`    | Execute an action                               |
| GET    | `/api/logs`      | Read logs (query: `tag`, `since`)               |
| GET    | `/api/actions`   | List all actions                                |
| GET    | `/api/config`    | Get server config                               |
| GET    | `/api/apps`      | List apps                                       |
| GET    | `/api/clients`   | List connected WebSocket clients                |
| GET    | `/api/dashboard` | VM metrics (memory, schedulers, processes, ETS) |

### JSON API Examples

```bash
# List all actions
curl http://localhost:4040/api/actions

# Execute an action
curl -X POST http://localhost:4040/api/action \
  -H "Content-Type: application/json" \
  -d '{"action": "task.list", "params": {}}'

# Evaluate code
curl -X POST http://localhost:4040/api/eval \
  -H "Content-Type: application/json" \
  -d '{"code": "Enum.sum(1..100)"}'

# Read action logs
curl "http://localhost:4040/api/logs?tag=action"

# Generic MCP request — get a resource
curl -X POST http://localhost:4040/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"resource": "actions"}'

# Generic MCP request — call a tool
curl -X POST http://localhost:4040/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"tool": "eval", "code": "Node.self()"}'
```

## Watcher

The Watcher (`Mooncore.MCP.Watcher`) is the in-memory log collector that backs both the dashboard UI and MCP log tools. It stores up to 1000 entries in a ring buffer.

### Logging Events

Log from anywhere in your application:

```elixir
Mooncore.MCP.Watcher.log(:custom, %{message: "Something happened"})
Mooncore.MCP.Watcher.log(:db, %{query: "FOR t IN tasks RETURN t", time_ms: 12})
Mooncore.MCP.Watcher.log(:error, %{action: "task.create", reason: "validation failed"})
```

The `:action` tag is used automatically by the action pipeline when dev tools are enabled, logging every action execution with params, auth, response, duration, and source (http/ws).

### Reading Logs

```elixir
# All logs (newest first)
Mooncore.MCP.Watcher.read()

# Filtered by tag
Mooncore.MCP.Watcher.read(:action)
Mooncore.MCP.Watcher.read(:lifecycle)

# Since a specific entry ID (for polling)
Mooncore.MCP.Watcher.read_since(42)
```

### Real-Time Watchers

Subscribe a process to receive logs as they happen:

```elixir
Mooncore.MCP.Watcher.add_watcher(self(), :action)

receive do
  {:mooncore_log, tag, entry} -> IO.inspect({tag, entry})
end

Mooncore.MCP.Watcher.remove_watcher(self())
```

### Log Entry Format

```elixir
%{
  id: 1,                          # unique, incrementing integer
  tag: :action,                   # tag atom
  data: %{action: "task.create"}, # your data
  ts: 1711827600000               # timestamp (milliseconds)
}
```

## Elixir API

You can call MCP Server functions directly from Elixir code:

```elixir
# Resources
Mooncore.MCP.Server.list_actions()
Mooncore.MCP.Server.list_clients()
Mooncore.MCP.Server.list_apps()
Mooncore.MCP.Server.server_info()

# Tools
Mooncore.MCP.Server.run_action("task.create", %{"title" => "Test"}, nil)
Mooncore.MCP.Server.eval_code("1 + 1")
Mooncore.MCP.Server.read_logs(%{"tag" => "action"})
Mooncore.MCP.Server.read_logs(%{"since_id" => 42})
Mooncore.MCP.Server.clear_logs()
Mooncore.MCP.Server.add_watcher_session(:action)
```

All functions require `config :mooncore, mooncore_dev_tools: true` and `MOONCORE_DEV_SECRET` to be set, and will return errors or throw when dev tools are off.
