defmodule Mooncore.Dev.Plug do
  @moduledoc """
  Development dashboard plug. Mount at `/mooncore` in your router.

  Provides:
  - HTML dashboard with MCP tools, log viewer, and IEx console
  - JSON API endpoints for MCP operations

  Only active when `config :mooncore, devmode: true`.

  ## Usage in your router

      # Add to your Plug.Router:
      forward "/mooncore", to: Mooncore.Dev.Plug
  """

  use Plug.Router

  plug(:check_devmode)

  plug(Plug.Parsers,
    parsers: [{:json, json_decoder: Jason}],
    pass: ["text/*", "application/json"]
  )

  plug(:match)
  plug(:dispatch)

  defp check_devmode(conn, _opts) do
    if Mooncore.config(:devmode, false) do
      conn
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "Not Found")
      |> halt()
    end
  end

  # ── HTML Dashboard ──

  get "/" do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, Mooncore.Dev.Page.render())
  end

  # ── JSON API ──

  post "/api/mcp" do
    result = Mooncore.MCP.Server.handle_request(conn.body_params)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(result))
  end

  post "/api/eval" do
    code = conn.body_params["code"] || ""
    result = Mooncore.MCP.Server.eval_code(code)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(result))
  end

  post "/api/action" do
    action = conn.body_params["action"]
    params = conn.body_params["params"] || %{}
    auth = conn.body_params["auth"]
    result = Mooncore.MCP.Server.run_action(action, params, auth)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(result))
  end

  get "/api/logs" do
    params = conn.query_params
    result = Mooncore.MCP.Server.read_logs(params)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{logs: result}))
  end

  get "/api/actions" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{actions: Mooncore.MCP.Server.list_actions()}))
  end

  get "/api/config" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{config: Mooncore.MCP.Server.server_info()}))
  end

  get "/api/apps" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{apps: Mooncore.MCP.Server.list_apps()}))
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
