# Philosophy

Mooncore was born from a simple observation: most web frameworks are designed around HTTP, but most applications are designed around **operations**. A user creates a task, sends a message, updates a setting — these are actions, not GET/POST/PUT/DELETE requests. The HTTP verb is just a transport detail.

## Actions Over Endpoints

In a traditional framework, you think in terms of routes:

```
GET    /api/tasks
POST   /api/tasks
PUT    /api/tasks/:id
DELETE /api/tasks/:id
```

Each route maps to a controller function that receives an HTTP request object and returns an HTTP response. Your business logic is tangled with the transport layer from the start.

In Mooncore, you think in terms of actions:

```elixir
"task.list"   => {MyApp.Action.Task, :list, ~w(user), %{}}
"task.create" => {MyApp.Action.Task, :create, ~w(user), %{}}
"task.update" => {MyApp.Action.Task, :update, ~w(user), %{}}
"task.delete" => {MyApp.Action.Task, :delete, ~w(admin), %{}}
```

Each action receives a request map and returns a result. It doesn't know or care about HTTP status codes, headers, or URL paths. The same action works over HTTP, WebSocket, or a direct function call.

This isn't just an aesthetic choice — it has real consequences:

- **Testing is simpler.** Call the action directly with a map. No need to build fake HTTP requests.
- **Real-time is free.** The same action that works over HTTP POST works over WebSocket with zero changes.
- **Reuse is natural.** Actions can call other actions. No need for service layers or internal APIs.
- **Protocol flexibility.** Add gRPC, MQTT, or any other protocol later without touching your action code.

## You Own the Edges

Mooncore doesn't own your HTTP layer. You write a standard `Plug.Router` and decide:

- What URLs map to actions
- Which plugs run in the pipeline
- How error responses look
- What HTTP status codes to return
- Whether to serve static files, health checks, or anything else

Mooncore provides `Endpoint.Http.handle/1` for the common case (POST an action name, get JSON back) and `Endpoint.Http.receive_action/1` when you want the raw result to format your own response.

This is a deliberate design choice. Frameworks that own the routing layer eventually need escape hatches for every edge case. Mooncore gives you the escape hatch as the default, and provides convenience functions on top.

## No Database, No Problem

Most frameworks ship with a database layer. Ecto in Phoenix, ActiveRecord in Rails, Django ORM in Django. This creates a deep coupling between your application and a specific database paradigm.

Mooncore ships with zero database opinions. You might use:

- Ecto with PostgreSQL
- ArangoDB with a custom client
- Redis for everything
- A REST API as your backend
- Multiple databases in the same app

Wire your database into the request pipeline using middleware:

```elixir
defmodule MyApp.Middleware.DB do
  @behaviour Mooncore.Middleware

  def call(req) do
    db = MyApp.DB.connect(req[:auth]["dkey"])
    Map.put(req, :db, db)
  end
end
```

Configure it once, and every action receives a `:db` key in its request map. No inheritance, no mixins, no base controller classes.

## Explicit Over Implicit

Mooncore avoids hidden behavior:

- **No code generation.** There's no `mix mooncore.gen.action` that creates files you'll need to understand and maintain.
- **No naming conventions.** There's no "if you name a module this way, it automatically becomes a controller." You explicitly map action names to functions.
- **No implicit middleware.** You choose which middleware runs before and after your actions by listing them in config.
- **No magic assigns.** The request map is a plain Elixir map. No special struct with hidden fields.

When something goes wrong, you read the code and understand it. There's no framework-level indirection to trace through.

## Multi-Tenancy as a First-Class Concept

Most frameworks bolt multi-tenancy on later. Mooncore builds it in from the start:

- JWT tokens carry `app`, `dkey` (domain key), and `scope` fields
- The action dispatcher routes to the correct app's action module based on the token
- WebSocket channels are scoped per domain and user
- The client registry tracks connections per group and channel

You can run multiple applications with different action sets, different roles, and different data scopes — all in the same Mooncore deployment.

## Middleware, Not Inheritance

In frameworks with controllers, shared behavior is typically handled through inheritance or mixins:

```
ApplicationController < ActionController::Base  # Rails
MyController extends Controller                  # Many frameworks
```

Mooncore uses composable middleware instead — plain modules with a `call/1` function:

```elixir
config :mooncore,
  before_action: [MyApp.Middleware.DB, MyApp.Middleware.Audit],
  after_action: [MyApp.Middleware.StripSensitive]
```

Before middlewares transform the request map. After middlewares transform the response. There's no class hierarchy, no `super` calls, no ordering ambiguity.

## Real-Time as Default

WebSocket support in Mooncore isn't a separate subsystem — it's the same action pipeline. When a WebSocket message arrives with `"action": "task.create"`, it goes through the same middleware chain and dispatches to the same handler function as an HTTP request.

The WebSocket layer adds:

- **Channels** — clients join named channels, messages broadcast to all members
- **Binary protocol** — send metadata + binary payload (files, images) over the same connection
- **JWT auth over WebSocket** — authenticate after connection with `["jwt", token]`
- **Pub/sub** — publish from anywhere in the app with `Socket.publish/3`

This design means you don't need separate controllers for HTTP and WebSocket. Write the action once, and both transports work.

## Small Surface Area

Mooncore's public API is intentionally small:

- `Mooncore.Action` — define and dispatch actions
- `Mooncore.Middleware` — before/after hooks
- `Mooncore.Auth.Token` — create and verify JWTs
- `Mooncore.Auth.Plug` — extract auth from HTTP requests
- `Mooncore.Endpoint.Http` — HTTP adapter
- `Mooncore.Endpoint.Socket` — WebSocket adapter
- `Mooncore.App` — multi-app registry

That's about 7 modules you need to understand. The rest (`Clients`, `Handler`, `Base58`, `Deflist`) are internal machinery that you rarely interact with directly.

A small surface area means less documentation to read, fewer things to break on upgrades, and less framework-specific knowledge to carry in your head.

## The Mooncore Way

1. **Define your actions** — a flat map of names to handler functions
2. **Write your handlers** — plain functions that take a map and return a map
3. **Set up your router** — a standard Plug.Router, your way
4. **Add middleware** — for cross-cutting concerns like DB connections and logging
5. **Configure auth** — JWT with roles for access control
6. **Ship it** — Bandit serves your app, Mooncore dispatches your actions
