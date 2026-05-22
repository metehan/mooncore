defmodule Mooncore.MCP.Server do
  @moduledoc """
  MCP (Model Context Protocol) server for AI observability.

  Everything is gated behind `MOONCORE_DEV_SECRET`. Nothing is exposed when the secret is not set.

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

  defp mooncore_dev_tools?, do: Mooncore.mooncore_dev_tools_enabled?()

  defp dev_tools_disabled do
    %{
      ok: """
      Dev tools are not active. To enable MCP:

      1. Add to your config:
           config :mooncore, mooncore_dev_tools: true, mcp_port: 4040

      2. Set the environment variable before starting the app:
           MOONCORE_DEV_SECRET=<your-secret>

      Both the config flag and the environment variable must be set.
      """
    }
  end

  # ── Read-only resources ──

  @doc "List all registered actions across all apps. Requires MOONCORE_DEV_SECRET."
  def list_actions do
    if not mooncore_dev_tools?(), do: throw(:mooncore_dev_tools_required)

    Mooncore.App.list()
    |> Enum.flat_map(fn {app_key, app_info} ->
      mod = app_info[:action_module]

      if mod && function_exported?(mod, :actions_map, 0) do
        mod.actions_map()
        |> Enum.map(fn {action_name, entry} ->
          action_entry(action_name, app_key, entry)
        end)
      else
        []
      end
    end)
  end

  # Normalize any entry format to a consistent map.
  # Handles: map, {Mod, :fn}, {Mod, :fn, roles}, {Mod, :fn, roles, overrides}, {Mod, :fn, roles, overrides, validate}
  defp action_entry(action_name, app_key, %{handler: {handler_mod, function}} = entry) do
    %{
      app: app_key,
      action: action_name,
      handler: "#{inspect(handler_mod)}.#{function}",
      arity: "map",
      roles: Map.get(entry, :roles, []),
      overrides: Map.get(entry, :overrides, %{}),
      validate: normalize_validate(Map.get(entry, :validate)),
      public: Map.get(entry, :roles, []) == []
    }
  end

  defp action_entry(action_name, app_key, entry) do
    size = tuple_size(entry)
    handler_mod = elem(entry, 0)
    function = elem(entry, 1)

    defaults = %{
      app: app_key,
      action: action_name,
      handler: "#{inspect(handler_mod)}.#{function}",
      arity: Integer.to_string(size)
    }

    case entry do
      {_, _} ->
        Map.merge(defaults, %{roles: [], overrides: %{}, validate: nil, public: true})

      {_, _, roles} ->
        Map.merge(defaults, %{roles: roles, overrides: %{}, validate: nil, public: roles == []})

      {_, _, roles, req_mod} ->
        Map.merge(defaults, %{
          roles: roles,
          overrides: req_mod,
          validate: nil,
          public: roles == []
        })

      {_, _, roles, overrides, validate} ->
        Map.merge(defaults, %{
          roles: roles,
          overrides: overrides,
          validate: normalize_validate(validate),
          public: roles == []
        })
    end
  end

  # Convert validate tuples to maps for JSON serialization.
  # Input: [{"field_name", [:required, :string, {:min_length, 2}]}]
  # Output: [%{name: "field_name", rules: ["required", "string", %{min_length: 2}]}]
  defp normalize_validate(nil), do: nil

  defp normalize_validate(validate) when is_list(validate) do
    Enum.map(validate, fn
      {name, rules} when is_list(rules) ->
        %{name: name, rules: normalize_rules(rules)}

      {name, rules} ->
        %{name: name, rules: [rules]}

      other ->
        other
    end)
  end

  defp normalize_validate({:nested, schema}) do
    %{nested: normalize_validate(schema)}
  end

  defp normalize_validate(other), do: other

  defp normalize_rules(rules) when is_list(rules) do
    Enum.map(rules, fn
      {:nested, schema} ->
        %{nested: normalize_validate(schema)}

      tuple when is_tuple(tuple) ->
        inspect(tuple)

      v ->
        v
    end)
  end

  defp normalize_rules(other), do: other

  @doc "Get connected client counts for a pool. Requires MOONCORE_DEV_SECRET."
  def list_clients(pool \\ nil) do
    if not mooncore_dev_tools?(), do: throw(:mooncore_dev_tools_required)

    pools =
      if pool,
        do: [if(is_binary(pool), do: String.to_existing_atom(pool), else: pool)],
        else: Mooncore.config(:pools, [:default])

    Enum.flat_map(pools, fn p ->
      Clients.list_all(p)
      |> Enum.map(fn {group, channels} ->
        channel_counts =
          Enum.map(channels, fn {channel, pids} ->
            %{channel: channel, count: length(pids)}
          end)

        %{
          pool: p,
          group: group,
          channels: channel_counts,
          total: Enum.sum(Enum.map(channel_counts, & &1.count))
        }
      end)
    end)
  end

  @doc "Get all registered apps (sanitized — no sensitive data). Requires MOONCORE_DEV_SECRET."
  def list_apps do
    if not mooncore_dev_tools?(), do: throw(:mooncore_dev_tools_required)

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

  @doc "Get current server configuration (sanitized). Requires MOONCORE_DEV_SECRET."
  def server_info do
    if not mooncore_dev_tools?(), do: throw(:mooncore_dev_tools_required)

    %{
      port: Mooncore.config(:port, 4000),
      pools: Mooncore.config(:pools, [:default]),
      router: inspect(Mooncore.config(:router)),
      app_module: inspect(Mooncore.config(:app_module)),
      before_action: inspect(Mooncore.config(:before_action, [])),
      after_action: inspect(Mooncore.config(:after_action, [])),
      watcher_count: Watcher.watcher_count(),
      log_count: length(Watcher.read())
    }
  end

  # ── Tools ──

  @doc """
  Run an action through the full pipeline. Requires MOONCORE_DEV_SECRET.

  ## Params
  - `action` — action name string
  - `params` — map of params to pass
  - `auth` — optional auth map (roles, user, app, tenant, scope)
  """
  def run_action(action, params \\ %{}, auth \\ nil) do
    if not Mooncore.mooncore_dev_tools_enabled?() do
      dev_tools_disabled()
    else
      request = %{
        params: Map.put(params, "action", action),
        auth: auth,
        source: "mcp"
      }

      try do
        Mooncore.Action.execute(action, request)
        |> Mooncore.Action.format_response()
      rescue
        e ->
          %{error: Exception.message(e), stacktrace: Exception.format(:error, e, __STACKTRACE__)}
      end
    end
  end

  @doc "Add a log watcher. Returns a reference for reading. Requires MOONCORE_DEV_SECRET."
  def add_watcher_session(tag_filter \\ nil) do
    if not Mooncore.mooncore_dev_tools_enabled?() do
      dev_tools_disabled()
    else
      Watcher.add_watcher(self(), tag_filter)
      %{ok: true, message: "Watcher added for pid #{inspect(self())}"}
    end
  end

  @doc "Read logs. Optional tag filter or since_id. Requires MOONCORE_DEV_SECRET."
  def read_logs(opts \\ %{}) do
    if not mooncore_dev_tools?(), do: throw(:mooncore_dev_tools_required)

    cond do
      opts["since_id"] -> Watcher.read_since(opts["since_id"])
      opts["tag"] -> Watcher.read(safe_to_atom(opts["tag"]))
      true -> Watcher.read()
    end
  end

  @doc "Clear all collected logs. Requires MOONCORE_DEV_SECRET."
  def clear_logs do
    if not mooncore_dev_tools?(), do: throw(:mooncore_dev_tools_required)
    Watcher.clear()
    %{ok: true}
  end

  @doc """
  Publish a WebSocket message to connected clients. Requires MOONCORE_DEV_SECRET.

  ## Params
  - `group` — the tenant/group to target (required)
  - `event` — event name string (required)
  - `message` — payload map or value (required)
  - `channels` — list of channel strings (default: ["main:default"])
  """
  def publish_socket(params) do
    if not mooncore_dev_tools?(), do: throw(:mooncore_dev_tools_required)

    group = params["group"]
    event = params["event"]
    message = params["message"]
    channels = params["channels"] || ["main:default"]

    if is_nil(group) or is_nil(event) or is_nil(message) do
      %{error: "group, event, and message are required"}
    else
      Mooncore.Endpoint.Socket.publish(group, {event, message}, channels)
      %{ok: true, group: group, event: event, channels: channels}
    end
  end

  @doc """
  Read WebSocket message logs with optional filters. Requires MOONCORE_DEV_SECRET.

  ## Options
  - `limit` — max entries (default 100, max 1000)
  - `user` — filter by username
  - `channel` — filter by channel name
  - `direction` — filter by "in", "out", or "publish"
  - `since_id` — only return entries after this id (for polling)
  """
  def read_socket_logs(opts \\ %{}) do
    if not mooncore_dev_tools?(), do: throw(:mooncore_dev_tools_required)

    limit = min(opts["limit"] || 100, 1000)

    base =
      if opts["since_id"] do
        Watcher.read_since(opts["since_id"])
        |> Enum.filter(fn e -> e.tag == :socket end)
      else
        Watcher.read(:socket)
      end

    base
    |> then(fn logs ->
      if opts["user"],
        do: Enum.filter(logs, fn e -> e.data[:user] == opts["user"] end),
        else: logs
    end)
    |> then(fn logs ->
      if opts["channel"],
        do:
          Enum.filter(logs, fn e ->
            opts["channel"] in (e.data[:channels] || [])
          end),
        else: logs
    end)
    |> then(fn logs ->
      if opts["direction"],
        do: Enum.filter(logs, fn e -> to_string(e.data[:direction]) == opts["direction"] end),
        else: logs
    end)
    |> Enum.take(limit)
  end

  @doc """
  Evaluate Elixir code in the running application. mooncore_dev_tools only.
  Returns the result or error.
  """
  def eval_code(code) when is_binary(code) do
    if not Mooncore.mooncore_dev_tools_enabled?() do
      dev_tools_disabled()
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
  Tools (mooncore_dev_tools): run_action, add_watcher, read_logs, clear_logs, eval
  """
  def handle_request(params) do
    if not mooncore_dev_tools?() do
      dev_tools_disabled()
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
    ArgumentError -> nil
  end

  defp safe_to_atom(atom) when is_atom(atom), do: atom
end
