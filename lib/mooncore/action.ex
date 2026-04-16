defmodule Mooncore.Action do
  @moduledoc """
  Action dispatcher framework.

  `use Mooncore.Action` in your app's action module to get the standard
  dispatcher pattern with role checking, deep merge, and command fallback.

  ## Usage

      defmodule MyApp.Action do
        @actions %{
          "task.create" => {MyApp.Action.Task, :create, ~w(user), %{}},
          "task.list"   => {MyApp.Action.Task, :list, ~w(user), %{}},
          "echo"        => {MyApp.Action.Echo, :echo, [], %{}},
        }

        use Mooncore.Action
      end

  > **Important:** `@actions` must be defined **before** `use Mooncore.Action`.
  > The macro captures `@actions` at compile time — if it's defined after,
  > `actions_map/0` will return `nil` and nothing will dispatch.

  Actions are defined as:

      "action.name" => {Module, :function, required_roles, request_modifications}

  - `required_roles` — list of role strings. `[]` means public (no auth needed).
  - `request_modifications` — map deep-merged into the request before calling the handler.

  ## Request Map Structure

  The request map passed to handlers looks like:

      %{
        auth: %{"user" => "alice", "app" => "myapp", "roles" => ["user"], ...},
        params: %{                        # the FULL request body / message
          "action" => "task.create",     # action name lives here too
          "title" => "My Task",          # user data is at the top level
          "rayid" => "abc-123"           # (WebSocket only) correlation id
        }
      }

  `req[:params]` is the entire parsed request body (HTTP) or the full
  WebSocket message. User-supplied fields sit alongside `"action"`.

  ## Calling Actions

      # Via the pipeline (runs before/after middlewares):
      Mooncore.Action.execute("task.create", request_map)

      # Direct (no middlewares):
      MyApp.Action.run("task.create", request_map)
  """

  defmacro __using__(_opts) do
    quote do
      import Mooncore.Action, only: [check_roles: 2]

      Module.register_attribute(__MODULE__, :actions, accumulate: false)

      def run(action, request) do
        Mooncore.Action.dispatch(__MODULE__, action, request)
      end

      def actions_map do
        @actions
      end
    end
  end

  @doc """
  Execute an action through the full pipeline (before hooks → dispatch → after hooks).
  Called by transport adapters (HTTP, WebSocket).

  When `params["mooncore_log"]` is truthy, logs the entire lifecycle with timestamps.
  """
  def execute(action, request) do
    request = enrich_request(action, request)

    should_log =
      get_in(request, [:params, "mooncore_log"]) == true or
        get_in(request, [:params, "mooncore_log"]) == "true"

    log_entry = if should_log, do: lifecycle_start(action, request), else: nil

    start = System.monotonic_time(:millisecond)
    previous_execute = Process.get(:mooncore_action_execute)

    Process.put(:mooncore_action_execute, true)

    try do
      result =
        request
        |> run_hooks(:before_action)
        |> tap(fn req -> if log_entry, do: lifecycle_phase(log_entry, :after_hooks, req) end)
        |> then(fn req -> dispatch_to_app(action, req) end)
        |> tap(fn resp -> if log_entry, do: lifecycle_phase(log_entry, :action_result, resp) end)
        |> run_hooks(:after_action)
        |> tap(fn resp -> if log_entry, do: lifecycle_end(log_entry, resp) end)

      Mooncore.Dev.RequestLogger.log_action(
        action,
        request,
        result,
        System.monotonic_time(:millisecond) - start
      )

      result
    after
      restore_process_flag(:mooncore_action_execute, previous_execute)
    end
  end

  defp lifecycle_start(action, request) do
    entry = %{
      id: System.unique_integer([:positive]),
      action: action,
      started_at: System.monotonic_time(:microsecond),
      wall_time: :os.system_time(:milli_seconds),
      request: sanitize_for_log(request),
      phases: []
    }

    Mooncore.MCP.Watcher.log(:lifecycle, %{
      phase: :start,
      action: action,
      entry_id: entry.id,
      request: entry.request
    })

    entry
  end

  defp lifecycle_phase(entry, phase, data) do
    elapsed = System.monotonic_time(:microsecond) - entry.started_at

    Mooncore.MCP.Watcher.log(:lifecycle, %{
      phase: phase,
      action: entry.action,
      entry_id: entry.id,
      elapsed_us: elapsed,
      data: sanitize_for_log(data)
    })
  end

  defp lifecycle_end(entry, response) do
    elapsed = System.monotonic_time(:microsecond) - entry.started_at

    Mooncore.MCP.Watcher.log(:lifecycle, %{
      phase: :complete,
      action: entry.action,
      entry_id: entry.id,
      elapsed_us: elapsed,
      response: sanitize_for_log(response)
    })
  end

  defp sanitize_for_log(data) when is_map(data) do
    data
    |> Map.drop([:password, "password", :secret, "secret"])
    |> Enum.map(fn
      {k, v} when is_pid(v) -> {k, inspect(v)}
      {k, %Plug.Conn{}} -> {k, "<conn>"}
      {k, v} -> {k, v}
    end)
    |> Map.new()
  rescue
    _ -> inspect(data)
  end

  defp sanitize_for_log(data), do: data

  @doc """
  Dispatch an action through the app registry routing.
  Determines which app's action module handles the request based on auth.
  """
  def dispatch_to_app(action, request) do
    case Mooncore.App.info(request[:auth]["app"]) do
      %{action_module: action_module} ->
        action_module.run(action, request)

      _ ->
        if is_binary(action) and String.starts_with?(action, "public.") do
          dispatch_public(action, request)
        else
          # No app matched — try the first registered action module or return error
          dispatch_fallback(action, request)
        end
    end
  end

  @doc """
  Dispatch within a specific action module. Called by `use Mooncore.Action` generated `run/2`.
  This is the core dispatcher — role check, deep merge, apply.
  """
  def dispatch(module, action, request) do
    request = enrich_request(action, request)

    if Process.get(:mooncore_action_execute) || Process.get(:mooncore_direct_dispatch) do
      do_dispatch(module, action, request)
    else
      previous_direct = Process.get(:mooncore_direct_dispatch)
      start = System.monotonic_time(:millisecond)

      Process.put(:mooncore_direct_dispatch, true)

      try do
        result = do_dispatch(module, action, request)

        Mooncore.Dev.RequestLogger.log_action(
          action,
          request,
          result,
          System.monotonic_time(:millisecond) - start
        )

        result
      after
        restore_process_flag(:mooncore_direct_dispatch, previous_direct)
      end
    end
  end

  defp do_dispatch(module, action, request) do
    case Map.get(module.actions_map(), action) do
      {handler_mod, function, [], req_mod} ->
        merged_request = deep_merge_request(request, req_mod)
        apply(handler_mod, function, [merged_request])

      {handler_mod, function, action_roles, req_mod} ->
        if check_roles(request[:auth]["roles"], action_roles) do
          merged_request = deep_merge_request(request, req_mod)
          apply(handler_mod, function, [merged_request])
        else
          %{error: "Access denied"}
        end

      nil ->
        maybe_run_command(module, action, request)
    end
  end

  @doc "Check if user has any of the required roles."
  def check_roles(nil, _), do: false

  def check_roles(user_roles, allowed_roles) do
    Enum.any?(allowed_roles, &Enum.member?(user_roles, &1))
  end

  @doc "Format action responses for transport."
  def format_response(response) do
    case response do
      {:ok, r} -> r
      {:error, e} -> %{error: e}
      {:error, e, log_id} -> %{error: e, log_id: log_id}
      _ -> response
    end
  end

  # Dispatch public actions: "public.{app}.{function}"
  defp dispatch_public(action, request) do
    case String.split(action, ".") do
      [_, app, function] ->
        case Mooncore.App.info(app) do
          %{public_actions: action_module} ->
            function_atom = String.to_existing_atom(function)
            apply(action_module, function_atom, [request])

          _ ->
            %{error: "No public actions"}
        end

      _ ->
        %{error: "Invalid public action format"}
    end
  end

  # Fallback: try command pattern "module.function"
  defp dispatch_fallback(action, request) do
    # Check if any registered app's action module has this action
    Mooncore.App.list()
    |> Map.values()
    |> Enum.find_value(fn app_info ->
      mod = app_info[:action_module]

      if mod && Map.has_key?(mod.actions_map(), action) do
        mod.run(action, request)
      end
    end) || %{error: "Undefined action"}
  end

  # Command fallback: "module.function" → App.Command.Module.function/1
  defp maybe_run_command(module, command, request) do
    parent_namespace =
      module
      |> Module.split()
      |> Enum.drop(-1)
      |> Module.concat()

    case String.split(command, ".") do
      [module_short, function_str] ->
        cmd_module = Module.concat([parent_namespace, Command, String.capitalize(module_short)])
        function = String.to_atom(function_str)

        if Code.ensure_loaded?(cmd_module) and function_exported?(cmd_module, function, 1) do
          if check_roles(request[:auth]["roles"], ["run_command"]) do
            apply(cmd_module, function, [request])
          else
            %{error: "Access denied"}
          end
        else
          %{error: "Undefined action"}
        end

      _ ->
        %{error: "Unknown action"}
    end
  end

  defp run_hooks(data, hook_type) do
    Mooncore.config(hook_type, [])
    |> Enum.reduce(data, fn mod, acc -> mod.call(acc) end)
  end

  defp deep_merge_request(request, nil), do: request

  defp deep_merge_request(request, req_mod) when req_mod == %{}, do: request

  defp deep_merge_request(request, req_mod) do
    Map.merge(request, req_mod, &deep_merge/3)
  end

  defp deep_merge(_key, val1, val2) when is_map(val1) and is_map(val2) do
    Map.merge(val1, val2)
  end

  defp deep_merge(_key, _val1, val2), do: val2

  defp enrich_request(action, request) do
    request
    |> Map.update(:params, %{"action" => action}, fn
      params when is_map(params) -> Map.put_new(params, "action", action)
      _ -> %{"action" => action}
    end)
    |> Map.put_new(:source, default_source(request))
  end

  defp default_source(request) do
    cond do
      is_binary(request[:source]) -> request[:source]
      is_atom(request[:source]) -> Atom.to_string(request[:source])
      Map.has_key?(request, :socket_pid) -> "ws"
      true -> "elixir"
    end
  end

  defp restore_process_flag(key, nil), do: Process.delete(key)
  defp restore_process_flag(key, previous), do: Process.put(key, previous)
end
