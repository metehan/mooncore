# REST with Mooncore

Mooncore is action-first, but it does not block REST. You own the router, so you can expose any REST surface you want and translate those requests into Mooncore actions.

The practical rule is simple: keep business logic in actions, and let REST be the HTTP shape on top.

## When to Use REST

Use REST when you already have HTTP clients, you want resource-oriented URLs, or you need to fit into an existing API contract.

Use actions when you want the same operation to work over HTTP, WebSocket, MCP, or direct Elixir calls without changing the handler.

## The Basic Pattern

Define your actions normally:

```elixir
defmodule MyApp.Action do
  @actions %{
    "task.list" => {MyApp.Action.Task, :list, [], %{}},
    "task.create" => {MyApp.Action.Task, :create, [], %{}},
    "task.get" => {MyApp.Action.Task, :get, [], %{}},
    "task.update" => {MyApp.Action.Task, :update, [], %{}},
    "task.delete" => {MyApp.Action.Task, :delete, [], %{}},
  }

  use Mooncore.Action
end
```

Then add REST routes in your own `Plug.Router` and call `Mooncore.Action.execute/2`.

```elixir
defmodule MyApp.Router do
  use Plug.Router

  plug Plug.Logger
  plug Mooncore.Auth.Plug
  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, {:json, json_decoder: Jason}],
    length: 100_000_000
  plug :match
  plug :dispatch

  get "/api/tasks" do
    result = Mooncore.Action.execute("task.list", %{
      auth: conn.assigns[:auth],
      params: %{}
    })

    send_resp(conn, 200, Jason.encode!(result))
  end

  post "/api/tasks" do
    result = Mooncore.Action.execute("task.create", %{
      auth: conn.assigns[:auth],
      params: conn.body_params
    })

    send_resp(conn, 201, Jason.encode!(result))
  end

  get "/api/tasks/:id" do
    result = Mooncore.Action.execute("task.get", %{
      auth: conn.assigns[:auth],
      params: %{"id" => conn.params["id"]}
    })

    send_resp(conn, 200, Jason.encode!(result))
  end

  put "/api/tasks/:id" do
    result = Mooncore.Action.execute("task.update", %{
      auth: conn.assigns[:auth],
      params: Map.merge(conn.body_params, %{"id" => conn.params["id"]})
    })

    send_resp(conn, 200, Jason.encode!(result))
  end

  delete "/api/tasks/:id" do
    _result = Mooncore.Action.execute("task.delete", %{
      auth: conn.assigns[:auth],
      params: %{"id" => conn.params["id"]}
    })

    send_resp(conn, 204, "")
  end

  match "/run" do
    Mooncore.Endpoint.Http.handle(conn)
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
```

## Recommended Shape

Keep the REST layer thin. A good REST route should:

1. Read params from `conn.params` or `conn.body_params`
2. Pass `auth` through from `conn.assigns[:auth]`
3. Call `Mooncore.Action.execute/2`
4. Return a status code and JSON response

That keeps authorization, middleware, and business logic in the action layer where it belongs.

## Status Codes

Mooncore does not force a REST status model for you. Pick the HTTP response that fits your API.

- `200` for reads and successful updates
- `201` for creates
- `204` for deletes with no response body
- `400` for validation failures
- `401` or `403` for auth failures
- `404` when a resource is missing

If you want Mooncore to handle the generic `/run` action endpoint, use `Mooncore.Endpoint.Http.handle/1`. If you want custom HTTP responses, call `Mooncore.Endpoint.Http.receive_action/1` or `Mooncore.Action.execute/2` directly and format the response yourself.

## Why This Works Well

REST stays a transport concern, while actions stay the application contract. That means the same action can still be called from WebSocket clients, MCP tools, or internal Elixir code without duplicating the handler.

If you later change your HTTP routes, the action names and handler code can stay the same.
