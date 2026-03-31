defmodule Mooncore.Dev.Plug do
  @moduledoc """
  Development dashboard and MCP server plug.

  Runs on a dedicated port (default 4040), separate from the main app.
  Provides:
  - HTML dashboard with MCP tools, log viewer, and IEx console
  - Standard MCP protocol endpoint (JSON-RPC 2.0 over Streamable HTTP)
  - JSON API endpoints for MCP operations

  Only active when `config :mooncore, devmode: true`.
  Automatically started on the configured `mcp_port` (default: 4040).

  ## Configuration

      config :mooncore,
        devmode: true,
        mcp_port: 4040   # default
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

  # ── Standard MCP Protocol (JSON-RPC 2.0, Streamable HTTP) ──

  post "/mcp" do
    body = conn.body_params

    case body do
      # Batch request (array)
      requests when is_list(requests) ->
        responses =
          requests
          |> Enum.map(&Mooncore.MCP.Protocol.handle/1)
          |> Enum.reject(&(&1 == :notification))

        if responses == [] do
          send_resp(conn, 202, "")
        else
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(responses))
        end

      # Single request
      request when is_map(request) ->
        case Mooncore.MCP.Protocol.handle(request) do
          :notification ->
            send_resp(conn, 202, "")

          response ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(response))
        end

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          400,
          Jason.encode!(%{
            jsonrpc: "2.0",
            id: nil,
            error: %{code: -32700, message: "Parse error"}
          })
        )
    end
  end

  get "/mcp" do
    send_resp(conn, 405, "Method Not Allowed")
  end

  delete "/mcp" do
    send_resp(conn, 405, "Method Not Allowed")
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
