# Middleware

Middleware in Mooncore is a simple concept: modules that transform the request before an action runs, or transform the response after it runs.

## The Behaviour

Every middleware implements the `Mooncore.Middleware` behaviour with a single callback:

```elixir
@callback call(map()) :: map()
```

That's it. A function that takes a map and returns a map.

## Before Middleware

Before middlewares receive the request map and must return a (possibly modified) request map. They run in order before the action handler is called.

### Example: Database Connection

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

Now every action receives a `:db` key in its request map.

### Example: Request Logging

```elixir
defmodule MyApp.Middleware.RequestLog do
  @behaviour Mooncore.Middleware

  @impl true
  def call(req) do
    require Logger
    Logger.info("Action: #{req[:params]["action"]} by #{req[:auth]["user"] || "anonymous"}")
    req
  end
end
```

### Example: Rate Limiting

```elixir
defmodule MyApp.Middleware.RateLimit do
  @behaviour Mooncore.Middleware

  @impl true
  def call(req) do
    user = req[:auth]["user"] || "anonymous"
    case MyApp.RateLimit.check(user) do
      :ok -> req
      :limited -> Map.put(req, :rate_limited, true)
    end
  end
end
```

Then check in your actions:

```elixir
def create(req) do
  if req[:rate_limited] do
    %{error: "Rate limited. Try again later."}
  else
    # normal logic
  end
end
```

### Example: Default Parameters

```elixir
defmodule MyApp.Middleware.Defaults do
  @behaviour Mooncore.Middleware

  @impl true
  def call(req) do
    params = req[:params] || %{}
    params = Map.put_new(params, "page", 1)
    params = Map.put_new(params, "per_page", 25)
    Map.put(req, :params, params)
  end
end
```

## After Middleware

After middlewares receive the action's response and must return a (possibly modified) response. They run in order after the action handler returns.

### Example: Strip Sensitive Fields

```elixir
defmodule MyApp.Middleware.StripSensitive do
  @behaviour Mooncore.Middleware

  @impl true
  def call(response) when is_map(response) do
    response
    |> Map.delete("password")
    |> Map.delete("secret_key")
    |> Map.delete("internal_id")
  end

  def call(response), do: response
end
```

### Example: Wrap Response

```elixir
defmodule MyApp.Middleware.Envelope do
  @behaviour Mooncore.Middleware

  @impl true
  def call(%{error: _} = response) do
    %{success: false, data: response}
  end

  def call(response) when is_map(response) do
    %{success: true, data: response}
  end

  def call(response), do: response
end
```

### Example: Response Timing

```elixir
defmodule MyApp.Middleware.Timing do
  @behaviour Mooncore.Middleware

  @impl true
  def call(response) when is_map(response) do
    Map.put(response, :server_time, :os.system_time(:milli_seconds))
  end

  def call(response), do: response
end
```

## Configuration

Register middleware in your config:

```elixir
config :mooncore,
  before_action: [
    MyApp.Middleware.DB,
    MyApp.Middleware.RequestLog,
    MyApp.Middleware.RateLimit
  ],
  after_action: [
    MyApp.Middleware.StripSensitive
  ]
```

### Execution Order

Before middlewares run top-to-bottom. After middlewares run top-to-bottom. The full pipeline:

```
Request → DB → RequestLog → RateLimit → [Action Handler] → StripSensitive → Response
```

## When to Use Middleware vs. Action Tuple Modifications

Both middleware and the action tuple's request modifications inject data into the request. Use them for different purposes:

**Middleware** — cross-cutting concerns that apply to all (or most) actions:
- Database connections
- Logging
- Rate limiting
- Default parameters

**Request modifications** — action-specific configuration:
- Different timeout values
- Different format preferences
- Different permission scopes

```elixir
# Middleware: applies to every action
config :mooncore, before_action: [MyApp.Middleware.DB]

# Request modification: applies to one action
"report.pdf" => {MyApp.Action.Report, :generate, ~w(user), %{format: "pdf"}}
"report.csv" => {MyApp.Action.Report, :generate, ~w(user), %{format: "csv"}}
```

## Middleware vs. Plugs

Plugs operate at the HTTP level — they see `Plug.Conn` structs.
Middleware operates at the action level — they see plain maps.

Use **plugs** for:
- CORS headers
- Request parsing
- Static file serving
- HTTP-specific concerns

Use **middleware** for:
- Business logic concerns
- Data transformations
- Things that should work the same over HTTP and WebSocket
