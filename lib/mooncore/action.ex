defmodule Mooncore.Action do
  @moduledoc """
  Action dispatcher framework.

  `use Mooncore.Action` in your app's action module to get the standard
  dispatcher pattern with role checking, deep merge, and command fallback.

  ## Usage

      defmodule MyApp.Action do
        @actions %{
          "task.create" => %{handler: {MyApp.Action.Task, :create}, roles: ~w(user)},
          "task.list"   => %{handler: {MyApp.Action.Task, :list}, roles: ~w(user)},
          "echo"        => %{handler: {MyApp.Action.Echo, :echo}},
        }

        use Mooncore.Action
      end

  > **Important:** `@actions` must be defined **before** `use Mooncore.Action`.
  > The macro captures `@actions` at compile time — if it's defined after,
  > `actions_map/0` will return `nil` and nothing will dispatch.

  Actions are defined as maps with the following keys:

  - `:handler` — `{Module, :function}` tuple **(required)**
  - `:roles` — list of role strings. Omit or set `[]` for public (no auth needed).
  - `:overrides` — map deep-merged into the request before calling the handler,
    **overriding** any incoming params with the same keys. Use this to force
    server-controlled values (e.g. `%{format: "pdf"}`) regardless of what
    the caller sends.
  - `:validate` — a `Mooncore.Validate` schema (keyword list of `field: [rules]`)
    applied to `params` **before** the handler is called. If validation fails,
    an error is returned immediately without reaching the handler.

  ### Overrides Example

  Both routes call the same handler but force different config:

      @actions %{
        "report.pdf"     => %{handler: {MyApp.Action.Report, :generate}, roles: ~w(admin), overrides: %{format: "pdf"}},
        "report.preview" => %{handler: {MyApp.Action.Report, :generate}, roles: ~w(user),  overrides: %{format: "html"}},
      }

  The handler reads `req[:format]` — callers cannot override it.

  ### Validate Example

      @actions %{
        "task.create" => %{
          handler:  {MyApp.Action.Task, :create},
          roles:    ~w(user),
          validate: [
            {"title",    [:required, :string, {:min_length, 2}]},
            {"priority", [:integer, {:in, [1, 2, 3]}]}
          ]
        }
      }

  On failure the caller receives `%{error: "validation_failed", errors: %{"title" => ["is required"]}}`.
  Use string keys to match HTTP/WebSocket params; atom keys for internal Elixir calls;
  list paths (`["address", "city"]`) for nested maps.

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

  @sensitive_keys [
    :password,
    "password",
    :secret,
    "secret",
    :token,
    "token",
    :private_key,
    "private_key",
    :api_key,
    "api_key"
  ]

  defp sanitize_for_log(data) when is_map(data) do
    data
    |> Map.drop(@sensitive_keys)
    |> Enum.map(fn
      {k, v} when is_pid(v) -> {k, inspect(v)}
      {k, %Plug.Conn{}} -> {k, "<conn>"}
      {k, v} when is_map(v) -> {k, sanitize_for_log(v)}
      {k, v} -> {k, v}
    end)
    |> Map.new()
  rescue
    _ -> inspect(data)
  end

  defp sanitize_for_log(data), do: data

  @doc false
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

  @doc false
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
      # Map format: %{handler: {Mod, :func}, roles: [...], overrides: %{}, validate: [...]}
      %{handler: {handler_mod, function}} = entry ->
        roles = Map.get(entry, :roles, [])
        overrides = Map.get(entry, :overrides, %{})
        schema = Map.get(entry, :validate)

        cond do
          roles != [] and not check_roles(request[:auth]["roles"], roles) ->
            %{error: "Access denied"}

          schema != nil ->
            case validate_params(request[:params], schema) do
              :ok ->
                merged_request = deep_merge_request(request, overrides)
                apply(handler_mod, function, [merged_request])

              {:error, errors} ->
                %{error: "validation_failed", errors: errors}
            end

          true ->
            merged_request = deep_merge_request(request, overrides)
            apply(handler_mod, function, [merged_request])
        end

      # Legacy tuple format — multiple arities (backward compat)
      # {Mod, :fn}
      # {Mod, :fn, roles}
      # {Mod, :fn, roles, overrides}
      # {Mod, :fn, roles, overrides, validate}
      {handler_mod, function} ->
        apply(handler_mod, function, [request])

      {handler_mod, function, action_roles} ->
        if action_roles == [] or check_roles(request[:auth]["roles"], action_roles) do
          apply(handler_mod, function, [request])
        else
          %{error: "Access denied"}
        end

      {handler_mod, function, action_roles, req_mod} ->
        if action_roles == [] or check_roles(request[:auth]["roles"], action_roles) do
          merged_request = deep_merge_request(request, req_mod)
          apply(handler_mod, function, [merged_request])
        else
          %{error: "Access denied"}
        end

      {handler_mod, function, action_roles, req_mod, schema} ->
        cond do
          action_roles != [] and not check_roles(request[:auth]["roles"], action_roles) ->
            %{error: "Access denied"}

          schema != nil ->
            case validate_params(request[:params], schema) do
              :ok ->
                merged_request = deep_merge_request(request, req_mod)
                apply(handler_mod, function, [merged_request])

              {:error, errors} ->
                %{error: "validation_failed", errors: errors}
            end

          true ->
            merged_request = deep_merge_request(request, req_mod)
            apply(handler_mod, function, [merged_request])
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

  # Fallback: if auth includes an app claim that isn't registered, fail immediately
  # to prevent cross-app action leakage. Only search all apps when there is no app
  # context at all (e.g. unauthenticated single-app setups).
  defp dispatch_fallback(action, request) do
    if get_in(request, [:auth, "app"]) do
      %{error: "Undefined action"}
    else
      Mooncore.App.list()
      |> Map.values()
      |> Enum.find_value(fn app_info ->
        mod = app_info[:action_module]

        if mod && Map.has_key?(mod.actions_map(), action) do
          mod.run(action, request)
        end
      end) || %{error: "Undefined action"}
    end
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

  # Validates request params against an action schema.
  # String key normalization is handled inside Mooncore.Validate.
  defp validate_params(params, schema) when is_list(schema) do
    params = params || %{}

    case Mooncore.Validate.run_schema(params, schema) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  defp validate_params(_params, nil), do: :ok

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
