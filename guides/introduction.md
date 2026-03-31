# Introduction

Mooncore is a lightweight, action-based api framework for Elixir — a Phoenix alternative that puts **actions** at the center of everything.

## Why Mooncore?

Phoenix is a great framework, but it carries a lot of weight. Controllers, views, templates, channels, LiveView, PubSub, Ecto integration — it's a full ecosystem. That's powerful, but not every project needs all of it.

Mooncore takes a different path. Instead of building around HTTP request/response cycles and MVC patterns, it builds around **actions** — named operations that are completely transport-agnostic. The same action works over HTTP, WebSocket, or a direct Elixir function call with zero changes.

## Core Ideas

- **Actions, not controllers.** Every feature is a named action (`"task.create"`, `"user.login"`). No controllers, no routes for each endpoint — just a flat map of action names to handler functions.

- **Transport-agnostic.** Your action code doesn't know or care whether it was called from an HTTP POST, a WebSocket message, or an internal Elixir call. The framework handles the transport layer; you write the logic.

- **You own the router.** Mooncore doesn't generate routes for you. You write a standard `Plug.Router`, decide what URLs you want, which plugs to use, and how responses look. Mooncore provides the building blocks — you assemble them.

- **No database opinions.** Mooncore doesn't ship with Ecto, doesn't assume you're using PostgreSQL, and doesn't generate migrations. Bring whatever database client you want and wire it up through middleware.

- **Minimal magic.** No code generation, no macros that hide control flow, no implicit conventions. What you see is what runs.

## What It Includes

| Component                  | Purpose                                                       |
| -------------------------- | ------------------------------------------------------------- |
| `Mooncore.Action`          | Action dispatcher with role checking and middleware pipeline  |
| `Mooncore.Auth`            | JWT RS256 authentication (token creation, verification, plug) |
| `Mooncore.Endpoint.Http`   | HTTP adapter — turns a Plug.Conn into an action call          |
| `Mooncore.Endpoint.Socket` | WebSocket adapter — pub/sub broadcasting and message routing  |
| `Mooncore.Middleware`      | Before/after hooks for request/response transformation        |
| `Mooncore.App`             | Multi-app registry — support multiple apps in one deployment  |
| `Mooncore.Dev`             | Development dashboard and MCP server for AI observability     |

## What It Doesn't Include

- No HTML templating engine
- No database layer or ORM
- No asset pipeline
- No code generators
- No LiveView equivalent
- No opinionated project structure

You bring your own tools for these. Mooncore handles the action dispatch, authentication, real-time communication, and the middleware pipeline that ties them together.

## Who Is It For?

Mooncore is built for developers who:

- Build API-first applications (JSON APIs, real-time backends, microservices)
- Want WebSocket support as a first-class citizen, not an add-on
- Prefer explicit code over convention-driven magic
- Need multi-tenant/multi-app support out of the box
- Want a framework that stays out of the way

If you're building a content website with server-rendered HTML, Phoenix is probably the better choice. If you're building a real-time API backend where actions are the primary abstraction, Mooncore gives you exactly what you need and nothing more.
