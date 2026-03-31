# Philosophy

Mooncore is built on a set of deliberate design choices. This guide explains the reasoning behind them — what problems they solve, what tradeoffs they accept, and why we think they're worth it.

## Operations, Not Resources

REST models your application as a collection of resources with CRUD operations. This works when your domain is simple — users, posts, comments — but breaks down as complexity grows. "Archive all tasks older than 30 days" isn't a resource operation. "Generate a report" isn't CRUD. "Transfer ownership" isn't a PUT on either the sender or the receiver.

You end up inventing pseudo-resources (`POST /api/task-archives`, `POST /api/transfers`) or stuffing RPC into REST clothes. The abstraction that was supposed to simplify your design now complicates it.

Mooncore starts from a different premise: your application is a set of **operations**. Each operation has a name, takes parameters, and returns a result. That's it. No mapping to HTTP verbs, no URL hierarchy, no debate about whether something is a resource or an action. If your app does it, give it a name and write the function.

This isn't anti-REST — it's post-REST. REST solved a real problem (interoperability between services in the early web). But for applications where you control both sides of the wire, the resource abstraction adds ceremony without value.

## Data In, Data Out

Every action handler in Mooncore has the same shape:

```elixir
def handler(req), do: result
```

The request is a map. The result is a map (or a tuple like `{:ok, map}` / `{:error, reason}`). No special request object, no response builder, no connection struct, no context object with hidden state.

This is a conscious rejection of the OOP pattern where frameworks hand you a "context" object loaded with methods:

```
# Typical framework pattern
def create(conn, params) do
  conn
  |> put_status(201)
  |> put_resp_header("location", "/tasks/#{id}")
  |> json(%{id: id})
end
```

The Mooncore equivalent:

```elixir
def create(req) do
  # ... create the task ...
  %{id: id}
end
```

The handler doesn't decide HTTP status codes. It doesn't set headers. It returns data, and the transport layer decides how to deliver it. This means the handler works identically whether called from HTTP, WebSocket, an Elixir function, or an AI agent through MCP. There's no `conn` to fake in tests — just call the function with a map.

Plain maps also compose naturally. A before-middleware adds keys to the request map. An after-middleware transforms the result map. No method chaining, no monadic wrappers, no `assign` vs `put_private` distinction. It's maps all the way down.

## Framework as Library

Most web frameworks own your application. They control the boot process, the routing, the middleware pipeline, the error handling, and the response format. You write code inside their structure. When you need something outside that structure, you search for escape hatches.

Mooncore inverts this. **You** own the application. You write a `Plug.Router` with whatever routes, middleware, and response formats you want. Mooncore provides functions you call when you need action dispatch, JWT verification, or WebSocket handling. Your router calls `Endpoint.Http.handle/1` — Mooncore doesn't call your router.

This means:

- You can serve static files, health checks, and webhooks in the same router alongside actions.
- You choose HTTP status codes and response shapes. Mooncore doesn't force `200 OK` with an error body or any other convention.
- You can use Mooncore for some routes and raw Plug for others in the same app.
- Swapping out the HTTP layer doesn't touch your action code.

The tradeoff is that Mooncore won't scaffold a project for you or generate routes from your action definitions. You write a few more lines of boilerplate in exchange for understanding exactly what your application does.

## No Database Layer

Mooncore has zero opinions about persistence. No ORM, no query builder, no schema DSL, no migration system.

This is usually the first thing people question. Every other framework ships with a database layer — Ecto in Phoenix, ActiveRecord in Rails, Prisma in Node. Why leave it out?

Because coupling your framework to a persistence model makes assumptions that might be wrong:

- What if your data lives in ArangoDB, not PostgreSQL?
- What if you use multiple databases in the same app?
- What if your backend is another API, not a database at all?
- What if different actions talk to different data sources?

Mooncore provides the mechanism to wire any data source you want into the request pipeline:

```elixir
# Middleware adds :db to every request
defmodule MyApp.Middleware.DB do
  @behaviour Mooncore.Middleware
  def call(req) do
    Map.put(req, :db, MyApp.DB.connection(req[:auth]["dkey"]))
  end
end
```

One line in config, and every action handler gets a `:db` key. Use Ecto, use a raw HTTP client, use an in-memory store — the framework doesn't care and doesn't need to.

## Composition Over Configuration

Mooncore avoids hidden behavior. There are no code generators, no naming conventions that trigger automatic behavior, and no implicit middleware. Everything is explicit:

- Actions are an explicit map of names to `{Module, :function, roles, opts}` tuples.
- Middleware is an explicit ordered list in config.
- The router is an explicit Plug.Router you wrote yourself.
- Auth is an explicit plug in your pipeline.

When something breaks, you read the code and trace the execution path. There's no "magic" — no runtime reflection discovering modules by name, no compile-time code generation you can't inspect, no framework-internal state you can't access.

The tradeoff: more typing upfront. You manually list your actions instead of the framework scanning your modules. You write your router instead of it being generated. This is intentional — the typing is trivial, and the clarity pays for itself the first time you debug a production issue.

Shared behavior happens through composition, not inheritance. Middleware modules are composed in a list. Action handlers are plain functions that can call other functions. There's no base controller, no `super` call chain, no mixin ordering ambiguity.

## Multi-Tenancy From the Start

Adding multi-tenancy to an existing framework is painful. You end up with tenant-scoping middleware, conditional database connections, and permission checks scattered across controllers.

Mooncore builds multi-tenancy into the core:

- JWT tokens carry `app`, `dkey` (domain key), and `scope` fields
- The action dispatcher routes to the correct app's action module based on the token
- WebSocket channels are scoped per domain
- The client registry tracks connections per group and channel

You can run multiple applications with different action sets, different roles, and different data scopes in a single deployment. This isn't a plugin or an add-on — it's how the dispatch system works.

## Real-Time Is Not Special

Many frameworks treat WebSocket as a separate subsystem. Phoenix has Channels alongside Controllers. Express has Socket.IO alongside routes. You end up with two parallel codepaths for the same operations.

In Mooncore, HTTP and WebSocket hit the same action pipeline. A JSON message over WebSocket with `"action": "task.create"` goes through the same middleware chain and dispatches to the same handler as an HTTP POST. The handler doesn't know which transport delivered the request, and it doesn't need to.

The WebSocket layer adds what real-time needs — channels, pub/sub, binary message support, connection-scoped auth — without creating a parallel universe for your application logic.

## Small Is a Feature

Mooncore's public API is about 7 modules. The entire framework is a handful of files. This is a feature, not a limitation.

A small surface area means:

- **Less to learn.** You can read the entire framework source in an afternoon.
- **Less to break.** Fewer moving parts means fewer things that can go wrong on upgrades.
- **Less to carry.** The framework-specific knowledge in your head stays small, leaving room for your actual domain.

The alternative — a framework that handles every concern — gives you more out of the box but demands more of your attention. Every feature is another thing to understand, configure, and maintain. Mooncore chooses to do a few things well and let you bring your own tools for the rest.

## The Tradeoffs

Every design choice has a cost. Here's what Mooncore trades away:

| You get | You give up |
|---|---|
| Transport-agnostic handlers | HTTP-specific features (streaming responses, SSE) require manual work |
| No database coupling | No schema validation, no migration generators, no query DSL |
| You own the router | No automatic route generation from action definitions |
| Explicit everything | More boilerplate for initial setup |
| Small framework | Fewer batteries included |
| Multi-tenancy built in | Single-tenant apps carry slight conceptual overhead |

These tradeoffs are deliberate. Mooncore is for developers who prefer a small, explicit foundation they fully understand over a large, capable framework they partially understand.
