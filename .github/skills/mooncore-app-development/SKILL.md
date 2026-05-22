---
name: mooncore-app-development
description: 'Build and extend applications with Mooncore. Use when creating Mooncore apps, adding actions, routers, middleware, auth, WebSocket features, MCP integration, or writing guides for Mooncore modules. Enforces Mooncore-specific patterns, prefers Mooncore MCP during development when available, requires matching ExUnit tests, and requires extensive runnable guides with single-expression Elixir or IEx code blocks.'
argument-hint: 'Describe the Mooncore app, module, or action set you want to build or document.'
user-invocable: true
---

# Mooncore App Development

Use this skill when building or extending an application that depends on Mooncore.

This skill does four things:

1. It keeps generated code aligned with Mooncore's actual architecture.
2. It prefers Mooncore MCP as the primary runtime inspection and action-execution interface during development when it is available.
3. It requires matching automated tests for new behavior, changed behavior, and bug fixes.
4. It treats documentation as part of the implementation by requiring runnable guides for every new `lib/` module that is introduced.

## When To Use

- Creating a new application with Mooncore
- Adding or changing an app registry module
- Adding or changing action modules
- Adding routers, HTTP endpoints, or WebSocket entry points
- Adding auth, middleware, MCP, or devtools integration
- Writing or updating guides for modules in a Mooncore app

## Non-Negotiable Mooncore Rules

- Mooncore is not Phoenix. Do not introduce Phoenix routers, channels, controllers, views, Ecto schemas, changesets, or LiveView patterns.
- Define `@actions` before `use Mooncore.Action`.
- Action handlers are plain functions that receive a request map.
- `req[:params]` is the full flat request body. Do not invent nested parameter conventions.
- Do not manually add Mooncore or Bandit to the application's supervision tree. Mooncore starts the HTTP server itself.
- Prefer transport-agnostic business logic. Keep HTTP and WebSocket concerns at the adapter layer.

## Required Workflow

1. Identify the Mooncore surface area involved.
2. If Mooncore MCP is available, use it throughout the task for discovery, runtime inspection, and action verification.
3. Generate code that matches Mooncore's architecture.
4. Create or update ExUnit tests in `test/` for every new behavior, changed behavior, or bug fix.
5. Create or update a guide in `guides/` for every new `lib/` module.
6. Make guide examples runnable in isolation.
7. Check that the tests, guides, and MCP-driven verification explain how a developer or agent can verify the module works.

## Step 1: Identify The Right Building Blocks

Choose the minimal Mooncore pieces needed for the task.

- For app registration, use a module implementing `Mooncore.App`.
- For action dispatch, use an action module with an `@actions` map and `use Mooncore.Action`.
- For HTTP routing, use `Plug.Router` and call Mooncore helpers from route handlers.
- For WebSocket support, use `WebSockAdapter` with `Mooncore.Endpoint.Socket.Handler`.
- For authentication, use `Mooncore.Auth.Plug` and `Mooncore.Auth.Token`.
- For shared request or response concerns, use Mooncore middleware modules.

## Step 2: Generate Code In Mooncore Style

Follow these implementation defaults unless the repository already uses a different established pattern.

- Keep actions flat and explicit, for example `"task.create"` or `"billing.invoice.list"`.
- Keep action handlers simple and functional.
- Put transport-specific adaptation in the router or socket layer, not in the business handler.
- Reuse the action pipeline instead of duplicating business logic per transport.
- If a module is meant to be used by developers directly, make its public entry points obvious and documented.

## Step 3: Use Mooncore MCP During Development

When `mooncore_dev_tools: true` is configured and `MOONCORE_DEV_SECRET` is set, Mooncore exposes an MCP server. Use it heavily during development.

Treat Mooncore MCP as the first runtime interface for agents when it is available.

Use MCP resources to inspect the running application:

- `mooncore://actions` to discover registered actions
- `mooncore://apps` to inspect app registry state
- `mooncore://config` to inspect sanitized runtime configuration
- `mooncore://clients` to inspect WebSocket client state when sockets are involved

Use MCP tools to exercise and debug behavior:

- `run_action` to execute actions through the full pipeline
- `read_logs` and `clear_logs` to inspect watcher output during debugging
- `eval` to inspect runtime state or verify small expressions in the running application

Prefer MCP over ad hoc HTTP requests when the goal is action discovery, action execution, or runtime inspection.

Use MCP before and after code changes when possible, but do not treat MCP as a replacement for ExUnit tests.

## Step 4: Write Tests

Tests are required work, not optional follow-up.

Whenever you add or change behavior, add or update ExUnit tests in `test/`.

At minimum, cover:

- the main success path
- validation or error behavior when relevant
- auth or role boundaries when relevant
- regression coverage for bug fixes

Prefer focused test files near the feature domain, such as:

- `test/my_app/action/users_test.exs`
- `test/my_app/auth/token_test.exs`
- `test/my_app/middleware/load_tenant_test.exs`

Do not substitute guide snippets, manual steps, or prose verification for automated tests.

If a behavior cannot be tested reasonably in the current repo, state that explicitly and still test the smallest pure function, action entry point, or boundary that proves the behavior.

## Step 5: Create Extensive Runnable Guides

Documentation is required work, not optional polish.

Whenever you add a new module under `lib/`, add a guide or expand the relevant existing guide in `guides/`.

Prefer one guide per module domain or closely related module set, such as:

- `guides/users.md`
- `guides/billing.md`
- `guides/chat.md`
- `guides/authentication.md`

Every guide should be extensive enough that a new developer can understand the module without reading the implementation first.

If several tiny internal modules belong to one coherent feature, document them together in one guide, but do not leave new `lib/` modules undocumented.

Each guide should cover:

- What the module or action group is for
- Which Mooncore primitives it depends on
- How requests flow through it
- Required auth roles, middleware, config, or transport assumptions
- How to call it from Elixir with `Mooncore.Action.execute/2` or the app's action module
- Runnable Elixir examples that cover HTTP-reachable behavior when the module is exposed over HTTP
- Runnable Elixir examples that cover WebSocket-reachable behavior when the module is exposed over sockets
- Expected request shape and response shape
- A short verification section that proves the module works

## Step 6: Guide Code Block Rules

This is mandatory.

- The Dev Tools Guides runner executes only code blocks tagged `elixir`, `ex`, `exs`, or `iex`.
- Use `elixir` or `iex` for runnable examples.
- Each runnable block must contain exactly one self-contained Elixir expression.
- Do not stack multiple Elixir expressions in one runnable block.
- Do not use `bash`, `sh`, `shell`, or `javascript` for examples that are meant to run inline in Guides.
- If a workflow needs multiple steps, split it into multiple runnable Elixir blocks with explanatory text between them.
- If you need to mention raw HTTP requests or WebSocket payloads, keep them secondary and clearly mark them as reference-only instead of the primary runnable example.

Good:

```elixir
Mooncore.Action.execute("task.list", %{params: %{"action" => "task.list"}, auth: nil})
```

```iex
Mooncore.Auth.Token.new_token(%{"user" => "alice", "app" => "myapp", "dkey" => "tenant1", "scope" => "default"}, ["admin", "user"], ["user"])
```

Bad:

- `curl -X POST http://localhost:4000/run -H 'content-type: application/json' -d '{"action":"task.list"}'`
- `ws.send(JSON.stringify({action: "task.list", rayid: "1"}))`
- A block that first aliases modules and then runs the actual example as a second expression

## Step 7: Match Guide Content To Module Type

Use the guide structure that fits the code.

For action modules:

- List the action names
- Show the `@actions` entries or summarize them clearly
- Explain required roles
- When MCP is available, exercise the action through `run_action` while developing
- Add ExUnit coverage for success, error, and role-gated paths when relevant
- Show at least one runnable Elixir invocation
- Explain transport behavior when relevant, but keep the verification path runnable in Elixir

For middleware modules:

- Explain what keys they add or change on the request or response
- Show configuration in `config/config.exs`
- Test the request or response transformation directly
- Show the expected data shape before and after the middleware runs with runnable Elixir examples when practical

For auth modules:

- Explain the token claims and role handling
- Show how the plug or token module is wired in
- Add ExUnit coverage for token generation, verification, and role decoding
- Show a single-expression Elixir or IEx verification example for token usage or request flow

For router or transport modules:

- Explain which routes or socket messages map into which actions
- Keep the transport layer thin
- Use MCP resources or logs to inspect the runtime mapping when available
- Test the transport mapping or the action boundary it delegates to, whichever is more stable in the repo
- Show at least one runnable Elixir example per supported transport mapping

For internal support modules that are not directly transport-facing:

- Explain why the module exists and which higher-level feature depends on it
- Show the public functions or integration points that matter
- Test the public functions directly
- Include at least one single-expression Elixir or IEx verification example when practical
- Link the module back to the guide for the action, middleware, auth, or transport layer that uses it

## Completion Checks

Before considering the task done, verify that:

- The generated code uses Mooncore concepts correctly
- No Phoenix or non-Mooncore abstractions were introduced by habit
- `@actions` appears before `use Mooncore.Action`
- If Mooncore MCP was available, it was used for runtime discovery or verification during development
- New or changed behavior has matching ExUnit coverage in `test/`
- Tests cover success, failure, and auth boundaries when relevant
- Every new `lib/` module is covered by a guide or an expanded guide section
- Guide examples are runnable and independently understandable
- Runnable guide code blocks use Elixir or IEx with one expression per block
- The guide includes a concrete verification path

## Default Output Shape

When using this skill, aim to produce:

- The implementation code
- Matching ExUnit tests in `test/`
- The corresponding guide updates in `guides/`
- Short notes about MCP availability and what was verified through it
- Short notes about verification status and remaining assumptions

## Suggested Prompt Patterns

- Build a Mooncore billing module with actions for invoice creation and listing, then write the tests and guide.
- Add JWT auth to this Mooncore app, use Mooncore MCP to inspect and verify it during development, and document the request flow with runnable examples.
- Create a WebSocket-backed notification module for Mooncore and add tests plus a guide with runnable Elixir examples.
- Review this Mooncore app for Phoenix-style mistakes and add missing guides for each action module.