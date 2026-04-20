defmodule Mooncore.MCP.Protocol do
  @moduledoc """
  Standard MCP (Model Context Protocol) JSON-RPC 2.0 handler.

  Implements the Streamable HTTP transport for VS Code and other MCP clients.
  All operations require mooncore_dev_tools to be enabled.

  ## Supported Methods

  - `initialize` — handshake with capabilities
  - `ping` — keepalive
  - `tools/list` — list available tools
  - `tools/call` — invoke a tool
  - `resources/list` — list available resources
  - `resources/read` — read a resource by URI
  """

  @protocol_version "2025-03-26"

  alias Mooncore.MCP.Server

  @doc """
  Handle a JSON-RPC 2.0 request map. Returns a response map.

  Notifications (no "id") return :notification.
  """
  def handle(%{"method" => method, "id" => id} = request) do
    params = request["params"] || %{}

    result = dispatch(method, params)

    case result do
      {:ok, value} -> jsonrpc_result(id, value)
      {:error, code, message} -> jsonrpc_error(id, code, message)
      {:error, code, message, data} -> jsonrpc_error(id, code, message, data)
    end
  end

  def handle(%{"method" => _method} = _request) do
    # Notification (no id) — acknowledge silently
    :notification
  end

  def handle(_) do
    jsonrpc_error(nil, -32600, "Invalid Request")
  end

  # ── MCP Methods ──

  defp dispatch("initialize", _params) do
    {:ok,
     %{
       protocolVersion: @protocol_version,
       capabilities: %{
         tools: %{},
         resources: %{}
       },
       serverInfo: %{
         name: "mooncore",
         version: Application.spec(:mooncore, :vsn) |> to_string()
       }
     }}
  end

  defp dispatch("ping", _params) do
    {:ok, %{}}
  end

  defp dispatch("tools/list", _params) do
    {:ok, %{tools: tools()}}
  end

  defp dispatch("tools/call", %{"name" => name} = params) do
    call_tool(name, params["arguments"] || %{})
  end

  defp dispatch("tools/call", _params) do
    {:error, -32602, "Missing required parameter: name"}
  end

  defp dispatch("resources/list", _params) do
    {:ok, %{resources: resources()}}
  end

  defp dispatch("resources/read", %{"uri" => uri}) do
    read_resource(uri)
  end

  defp dispatch("resources/read", _params) do
    {:error, -32602, "Missing required parameter: uri"}
  end

  defp dispatch(method, _params) do
    {:error, -32601, "Method not found: #{method}"}
  end

  # ── Tool Definitions ──

  defp tools do
    [
      %{
        name: "run_action",
        description: "Execute a Mooncore action through the full pipeline",
        inputSchema: %{
          type: "object",
          properties: %{
            action: %{type: "string", description: "Action name (e.g. 'task.create')"},
            params: %{type: "object", description: "Parameters to pass to the action"},
            auth: %{
              type: "object",
              description: "Optional auth map (roles, user, app, dkey, scope)"
            }
          },
          required: ["action"]
        }
      },
      %{
        name: "read_logs",
        description: "Read collected lifecycle/debug logs from the Watcher",
        inputSchema: %{
          type: "object",
          properties: %{
            tag: %{type: "string", description: "Filter by tag (e.g. 'lifecycle', 'error')"},
            since_id: %{type: "integer", description: "Only return logs after this ID"}
          }
        }
      },
      %{
        name: "clear_logs",
        description: "Clear all collected logs in the Watcher buffer",
        inputSchema: %{type: "object", properties: %{}}
      },
      %{
        name: "eval",
        description: "Evaluate Elixir code in the running application",
        inputSchema: %{
          type: "object",
          properties: %{
            code: %{type: "string", description: "Elixir code to evaluate"}
          },
          required: ["code"]
        }
      },
      %{
        name: "list_clients",
        description: "List connected WebSocket clients grouped by pool, group, and channel",
        inputSchema: %{
          type: "object",
          properties: %{
            pool: %{type: "string", description: "Pool name to query (default: all configured pools)"}
          }
        }
      },
      %{
        name: "read_socket_logs",
        description: "Read WebSocket message logs (incoming, outgoing, and server-publish events)",
        inputSchema: %{
          type: "object",
          properties: %{
            limit: %{type: "integer", description: "Max entries to return (default 100, max 1000)"},
            user: %{type: "string", description: "Filter by username"},
            channel: %{type: "string", description: "Filter by channel name (e.g. '@alice', 'main:default')"},
            direction: %{
              type: "string",
              enum: ["in", "out", "publish"],
              description: "Filter by message direction"
            },
            since_id: %{type: "integer", description: "Only return entries after this ID (for polling)"}
          }
        }
      },
      %{
        name: "publish_socket",
        description: "Publish a WebSocket message to connected clients in a group/channel",
        inputSchema: %{
          type: "object",
          properties: %{
            group: %{type: "string", description: "Group key (dkey) to target"},
            event: %{type: "string", description: "Event name (e.g. 'notification', 'task-updated')"},
            message: %{type: "object", description: "Payload to send"},
            channels: %{
              type: "array",
              items: %{type: "string"},
              description: "Target channels (default: ['main:default'])"
            }
          },
          required: ["group", "event", "message"]
        }
      }
    ]
  end

  # ── Tool Execution ──

  defp call_tool("run_action", args) do
    action = args["action"]
    params = args["params"] || %{}
    auth = args["auth"]
    result = Server.run_action(action, params, auth)
    {:ok, tool_result(inspect(result, pretty: true, limit: 200))}
  end

  defp call_tool("read_logs", args) do
    logs = Server.read_logs(args)
    {:ok, tool_result(inspect(logs, pretty: true, limit: 500))}
  end

  defp call_tool("clear_logs", _args) do
    Server.clear_logs()
    {:ok, tool_result("Logs cleared")}
  end

  defp call_tool("eval", %{"code" => code}) do
    result = Server.eval_code(code)

    case result do
      %{ok: true, result: text} -> {:ok, tool_result(text)}
      %{error: message} -> {:ok, tool_error(message)}
    end
  end

  defp call_tool("eval", _args) do
    {:error, -32602, "Missing required argument: code"}
  end

  defp call_tool("publish_socket", args) do
    result = Server.publish_socket(args)
    {:ok, tool_result(inspect(result, pretty: true))}
  end

  defp call_tool("list_clients", args) do
    result = Server.list_clients(args["pool"])
    {:ok, tool_result(Jason.encode!(result, pretty: true))}
  end

  defp call_tool("read_socket_logs", args) do
    result = Server.read_socket_logs(args)
    {:ok, tool_result(Jason.encode!(result, pretty: true))}
  end

  defp call_tool(name, _args) do
    {:error, -32602, "Unknown tool: #{name}"}
  end

  # ── Resource Definitions ──

  defp resources do
    [
      %{
        uri: "mooncore://actions",
        name: "Actions",
        description: "All registered actions across all apps",
        mimeType: "application/json"
      },
      %{
        uri: "mooncore://apps",
        name: "Apps",
        description: "Registered app configurations",
        mimeType: "application/json"
      },
      %{
        uri: "mooncore://clients",
        name: "Clients",
        description: "Connected WebSocket client counts",
        mimeType: "application/json"
      },
      %{
        uri: "mooncore://config",
        name: "Config",
        description: "Current Mooncore server configuration",
        mimeType: "application/json"
      }
    ]
  end

  # ── Resource Reading ──

  defp read_resource("mooncore://actions") do
    data = Server.list_actions()
    {:ok, resource_result("mooncore://actions", Jason.encode!(data))}
  end

  defp read_resource("mooncore://apps") do
    data = Server.list_apps()
    {:ok, resource_result("mooncore://apps", Jason.encode!(data))}
  end

  defp read_resource("mooncore://clients") do
    data = Server.list_clients()
    {:ok, resource_result("mooncore://clients", Jason.encode!(data))}
  end

  defp read_resource("mooncore://config") do
    data = Server.server_info()
    {:ok, resource_result("mooncore://config", Jason.encode!(data))}
  end

  defp read_resource(uri) do
    {:error, -32002, "Resource not found", %{uri: uri}}
  end

  # ── Response Helpers ──

  defp jsonrpc_result(id, result) do
    %{jsonrpc: "2.0", id: id, result: result}
  end

  defp jsonrpc_error(id, code, message) do
    %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}
  end

  defp jsonrpc_error(id, code, message, data) do
    %{jsonrpc: "2.0", id: id, error: %{code: code, message: message, data: data}}
  end

  defp tool_result(text) do
    %{content: [%{type: "text", text: text}], isError: false}
  end

  defp tool_error(text) do
    %{content: [%{type: "text", text: text}], isError: true}
  end

  defp resource_result(uri, text) do
    %{contents: [%{uri: uri, mimeType: "application/json", text: text}]}
  end
end
