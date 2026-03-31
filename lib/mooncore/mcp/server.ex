defmodule Mooncore.MCP.Server do
  @moduledoc """
  MCP (Model Context Protocol) server for AI observability.

  **Everything is gated behind devmode.** Nothing is exposed when devmode is off.

      config :mooncore, devmode: true

  ## Resources (read-only)
  - `actions` — list all registered actions across all apps
  - `clients` — connected WebSocket client counts per pool/group/channel
  - `apps` — registered app configurations
  - `config` — current Mooncore configuration (sanitized)

  ## Tools
  - `run_action` — execute an action with given params and auth
  - `add_watcher` — start collecting logs with optional tag filter
  - `read_logs` — read collected logs, optionally filtered by tag or since an id
  - `clear_logs` — clear the log buffer
  - `eval` — evaluate Elixir code in the running application
  """

  alias Mooncore.Endpoint.Socket.Clients
  alias Mooncore.MCP.Watcher

  defp devmode?, do: Mooncore.config(:devmode, false) == true

  # ── Read-only resources ──

  @doc "List all registered actions across all apps. Requires devmode."
  def list_actions do
    if not devmode?(), do: throw(:devmode_required)

    Mooncore.App.list()
    |> Enum.flat_map(fn {app_key, app_info} ->
      mod = app_info[:action_module]

      if mod && function_exported?(mod, :actions_map, 0) do
        mod.actions_map()
        |> Enum.map(fn {action_name, {handler_mod, function, roles, _req_mod}} ->
          %{
            app: app_key,
            action: action_name,
            handler: "#{inspect(handler_mod)}.#{function}",
            roles: roles,
            public: roles == []
          }
        end)
      else
        []
      end
    end)
  end

  @doc "Get connected client counts for a pool. Requires devmode."
  def list_clients(pool \\ :default) do
    if not devmode?(), do: throw(:devmode_required)

    Clients.list_all(pool)
    |> Enum.map(fn {group, channels} ->
      channel_counts =
        Enum.map(channels, fn {channel, pids} ->
          %{channel: channel, count: length(pids)}
        end)

      %{
        group: group,
        channels: channel_counts,
        total: Enum.sum(Enum.map(channel_counts, & &1.count))
      }
    end)
  end

  @doc "Get all registered apps (sanitized — no sensitive data). Requires devmode."
  def list_apps do
    if not devmode?(), do: throw(:devmode_required)

    Mooncore.App.list()
    |> Enum.map(fn {key, info} ->
      %{
        key: key,
        name: info[:name] || key,
        roles: info[:roles] || [],
        action_module: inspect(info[:action_module])
      }
    end)
  end

  @doc "Get current server configuration (sanitized). Requires devmode."
  def server_info do
    if not devmode?(), do: throw(:devmode_required)

    %{
      port: Mooncore.config(:port, 4444),
      pools: Mooncore.config(:pools, [:default]),
      router: inspect(Mooncore.config(:router)),
      app_module: inspect(Mooncore.config(:app_module)),
      devmode: Mooncore.config(:devmode, false),
      before_action: inspect(Mooncore.config(:before_action, [])),
      after_action: inspect(Mooncore.config(:after_action, [])),
      watcher_count: Watcher.watcher_count(),
      log_count: length(Watcher.read())
    }
  end

  # ── Tools (devmode) ──

  @doc """
  Run an action through the full pipeline. Devmode only.

  ## Params
  - `action` — action name string
  - `params` — map of params to pass
  - `auth` — optional auth map (roles, user, app, dkey, scope)
  """
  def run_action(action, params \\ %{}, auth \\ nil) do
    if not Mooncore.config(:devmode, false) do
      %{error: "run_action requires devmode"}
    else
      request = %{
        params: Map.put(params, "action", action),
        auth: auth
      }

      try do
        result = Mooncore.Action.execute(action, request)
        %{ok: true, result: Mooncore.Action.format_response(result)}
      rescue
        e ->
          %{error: Exception.message(e), stacktrace: Exception.format(:error, e, __STACKTRACE__)}
      end
    end
  end

  @doc "Add a log watcher. Returns a reference for reading. Devmode only."
  def add_watcher_session(tag_filter \\ nil) do
    if not Mooncore.config(:devmode, false) do
      %{error: "requires devmode"}
    else
      Watcher.add_watcher(self(), tag_filter)
      %{ok: true, message: "Watcher added for pid #{inspect(self())}"}
    end
  end

  @doc "Read logs. Optional tag filter or since_id. Requires devmode."
  def read_logs(opts \\ %{}) do
    if not devmode?(), do: throw(:devmode_required)

    cond do
      opts["since_id"] -> Watcher.read_since(opts["since_id"])
      opts["tag"] -> Watcher.read(safe_to_atom(opts["tag"]))
      true -> Watcher.read()
    end
  end

  @doc "Clear all collected logs. Requires devmode."
  def clear_logs do
    if not devmode?(), do: throw(:devmode_required)
    Watcher.clear()
    %{ok: true}
  end

  @doc """
  Evaluate Elixir code in the running application. Devmode only.
  Returns the result or error.
  """
  def eval_code(code) when is_binary(code) do
    if not Mooncore.config(:devmode, false) do
      %{error: "eval requires devmode"}
    else
      try do
        {result, _bindings} = Code.eval_string(code)
        %{ok: true, result: inspect(result, pretty: true, limit: 100)}
      rescue
        e -> %{error: Exception.message(e)}
      end
    end
  end

  # ── Request router ──

  @doc """
  Handle an MCP-style request. Returns a map response.

  Read resources: actions, clients, apps, config
  Tools (devmode): run_action, add_watcher, read_logs, clear_logs, eval
  """
  def handle_request(params) do
    if not devmode?() do
      %{error: "MCP server requires devmode"}
    else
      do_handle_request(params)
    end
  end

  defp do_handle_request(%{"resource" => "actions"}) do
    %{actions: list_actions()}
  end

  defp do_handle_request(%{"resource" => "clients"} = params) do
    pool = safe_to_atom(params["pool"] || "default")
    %{clients: list_clients(pool)}
  end

  defp do_handle_request(%{"resource" => "apps"}) do
    %{apps: list_apps()}
  end

  defp do_handle_request(%{"resource" => "config"}) do
    %{config: server_info()}
  end

  # Tools
  defp do_handle_request(%{"tool" => "run_action", "action" => action} = params) do
    run_action(action, params["params"] || %{}, params["auth"])
  end

  defp do_handle_request(%{"tool" => "add_watcher"} = params) do
    tag = if params["tag"], do: safe_to_atom(params["tag"]), else: nil
    add_watcher_session(tag)
  end

  defp do_handle_request(%{"tool" => "read_logs"} = params) do
    %{logs: read_logs(params)}
  end

  defp do_handle_request(%{"tool" => "clear_logs"}) do
    clear_logs()
  end

  defp do_handle_request(%{"tool" => "eval", "code" => code}) do
    eval_code(code)
  end

  defp do_handle_request(_) do
    %{
      error: "Unknown MCP request",
      resources: ["actions", "clients", "apps", "config"],
      tools: ["run_action", "add_watcher", "read_logs", "clear_logs", "eval"]
    }
  end

  defp safe_to_atom(str) when is_binary(str) do
    String.to_existing_atom(str)
  rescue
    _ -> String.to_atom(str)
  end

  defp safe_to_atom(atom) when is_atom(atom), do: atom
end
