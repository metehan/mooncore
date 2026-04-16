# Actions

Actions are the core abstraction in Mooncore. Every feature in your application is an action — a named operation mapped to a module function.

## Defining Actions

**Define `@actions` before `use Mooncore.Action`** — the macro captures the attribute at compile time:

```elixir
defmodule MyApp.Action do
  @actions %{
    "task.create"    => {MyApp.Action.Task, :create, ~w(user admin), %{}},
    "task.list"      => {MyApp.Action.Task, :list, ~w(user admin), %{}},
    "task.delete"    => {MyApp.Action.Task, :delete, ~w(admin), %{}},
    "user.profile"   => {MyApp.Action.User, :profile, ~w(user admin), %{}},
    "echo"           => {MyApp.Action.Echo, :echo, [], %{}},
    "health.check"   => {MyApp.Action.Health, :check, [], %{}},
  }

  use Mooncore.Action
end
```

> If `@actions` is defined **after** `use Mooncore.Action`, the `actions_map/0`
> function will return `nil` and no actions will dispatch. This is silent — no
> compile error — so always put `@actions` first.

### Action Tuple Format

```elixir
"action.name" => {HandlerModule, :function, required_roles, request_modifications}
```

| Field                   | Type   | Description                                  |
| ----------------------- | ------ | -------------------------------------------- |
| `HandlerModule`         | module | The module containing the handler function   |
| `:function`             | atom   | The function name to call                    |
| `required_roles`        | list   | Role strings. `[]` = public (no auth needed) |
| `request_modifications` | map    | Merged into request before calling handler   |

### Request Modifications

The fourth element lets you inject extra data into the request for specific actions:

```elixir
@actions %{
  "report.generate" => {MyApp.Action.Report, :generate, ~w(admin), %{
    format: "pdf",
    timeout: 30_000
  }},
  "report.preview" => {MyApp.Action.Report, :generate, ~w(user), %{
    format: "html",
    timeout: 5_000
  }},
}
```

Both actions call the same function, but with different configuration merged into the request. The handler reads `req[:format]` and `req[:timeout]` without knowing where they came from.

## Writing Handlers

Action handlers are plain functions. They receive a request map and return a result.
Access params with `req[:params]["key"]` — the user data and `"action"` key are at the same level:

```elixir
defmodule MyApp.Action.Task do
  def create(req) do
    # req[:params] = %{"action" => "task.create", "title" => "...", ...}
    db = req[:db]  # injected by middleware
    auth = req[:auth]

    case db.insert("tasks", %{
      title: req[:params]["title"],
      created_by: auth["user"]
    }) do
      {:ok, task} -> %{ok: true, task: task}
      {:error, reason} -> %{error: reason}
    end
  end

  def list(req) do
    db = req[:db]
    tasks = db.query("FOR t IN tasks RETURN t")
    %{tasks: tasks}
  end

  def delete(req) do
    db = req[:db]
    id = req[:params]["id"]
    db.delete("tasks", id)
    %{ok: true}
  end
end
```

### What's in the Request Map?

The request map contains everything the handler needs:

```elixir
%{
  auth: %{                    # JWT claims (nil if unauthenticated)
    "user" => "alice",
    "app" => "myapp",
    "dkey" => "my-domain",
    "scope" => "default",
    "roles" => ["user", "admin"]
  },
  params: %{                  # the FULL request body / WS message
    "action" => "task.create",  # action name lives here too
    "title" => "My Task",       # user data at the top level
    "rayid" => "abc-123"        # (WebSocket only) correlation id
  },
  # Additional keys from middleware:
  db: #DBConnection<...>,     # from MyApp.Middleware.DB
  # Additional keys from request_modifications:
  format: "pdf",              # from action tuple
  timeout: 30_000
}
```

`req[:params]` is the entire parsed request body (HTTP) or the full WebSocket
message. User-supplied fields sit alongside the `"action"` key — there is no
extra nesting level.

### Return Values

Actions can return any value. The framework handles these patterns:

```elixir
# Plain map — returned as-is
%{tasks: [...]}

# Tuple — unwrapped by format_response
{:ok, %{task: task}}          # → %{task: task}
{:error, "not found"}         # → %{error: "not found"}
{:error, "failed", "log-123"} # → %{error: "failed", log_id: "log-123"}

# Anything else — returned as-is
[1, 2, 3]
"ok"
42
```

## Execution Pipeline

When an action is called, it goes through this pipeline:

```
Request Map
    │
    ▼
Before Middlewares (in order)
    │
    ▼
App Routing (which action module?)
    │
    ▼
Role Check (does user have required role?)
    │
    ▼
Request Modifications (deep merge)
    │
    ▼
Handler Function (your code)
    │
    ▼
After Middlewares (in order)
    │
    ▼
Result
```

### Calling Actions

There are two ways to call an action:

**Through the pipeline** (recommended for transport adapters):

```elixir
# Runs before/after middlewares, routes to correct app
result = Mooncore.Action.execute("task.create", %{
  auth: auth_map,
  params: %{"title" => "My Task"}
})
```

**Direct dispatch** (skips middlewares):

```elixir
# Calls the handler directly, only role check + request mods
result = MyApp.Action.run("task.create", %{
  auth: auth_map,
  params: %{"title" => "My Task"}
})
```

## Role Checking

If an action defines required roles, the user must have at least one of them:

```elixir
# User needs "user" OR "admin" role
"task.create" => {MyApp.Action.Task, :create, ~w(user admin), %{}}

# User needs "admin" role
"task.delete" => {MyApp.Action.Task, :delete, ~w(admin), %{}}

# No auth required — anyone can call this
"echo" => {MyApp.Action.Echo, :echo, [], %{}}
```

If the user doesn't have a required role, the action returns `%{error: "Access denied"}` without calling the handler.

Roles are extracted from the JWT token's Base58-encoded bitmask (see [Authentication Guide](authentication.md)).

## Multi-App Routing

Mooncore supports multiple apps in the same deployment. When an action is executed through the pipeline, the framework:

1. Reads `auth["app"]` from the JWT claims
2. Looks up the app in `Mooncore.App.info/1`
3. Routes to that app's `action_module`
4. Dispatches the action within that module

This means different apps can have different action sets, different roles, and different handlers — all served by the same Mooncore instance.

```elixir
defmodule MyPlatform.App do
  @behaviour Mooncore.App

  @impl true
  def list do
    %{
      "app_a" => %{
        key: "app_a",
        action_module: AppA.Action,
        roles: ["user", "editor"]
      },
      "app_b" => %{
        key: "app_b",
        action_module: AppB.Action,
        roles: ["viewer", "manager"]
      }
    }
  end

  @impl true
  def info(name), do: Map.get(list(), name)
end
```

## Command Fallback

If an action name isn't found in the action map, Mooncore tries a command fallback. If the action module defines a `command/2` function, it's called with the action name and request:

```elixir
defmodule MyApp.Action do
  @actions %{
    "task.create" => {MyApp.Action.Task, :create, ~w(user), %{}},
  }

  use Mooncore.Action

  # Catches any action not in @actions
  def command(action_name, request) do
    %{error: "Unknown action: #{action_name}"}
  end
end
```

This is useful for dynamic action routing, forwarding to external services, or providing custom error responses.

## Lifecycle Logging

When `params["mooncore_log"]` is set to `true`, the action pipeline logs the entire lifecycle with timestamps to the Watcher (see [Dev Tools Guide](devtools.md)):

```bash
curl -X POST http://localhost:4000/run \
  -H "Content-Type: application/json" \
  -d '{"action": "task.create", "title": "Test", "mooncore_log": true}'
```

This logs:
- `:start` — action name and sanitized request
- `:after_hooks` — request state after before-middlewares
- `:action_result` — raw handler result
- `:complete` — final response with elapsed time in microseconds

View these logs in the dev dashboard or via the MCP server.
