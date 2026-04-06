defmodule Mooncore.Dev.Plug do
  @moduledoc """
  Development dashboard and MCP server plug.

  Runs on a dedicated port (default 4040), separate from the main app.
  Provides:
  - HTML dashboard with MCP tools, log viewer, and IEx console
  - Standard MCP protocol endpoint (JSON-RPC 2.0 over Streamable HTTP)
  - JSON API endpoints for MCP operations

  Only active when `config :mooncore, mooncore_dev_tools: true`.
  Automatically started on the configured `mcp_port` (default: 4040).

  ## Configuration

      config :mooncore,
        mooncore_dev_tools: true,
        mcp_port: 4040   # default
  """

  use Plug.Router

  plug(:check_mooncore_dev_tools)

  plug(Plug.Parsers,
    parsers: [{:json, json_decoder: Jason}],
    pass: ["text/*", "application/json"]
  )

  plug(:match)
  plug(:dispatch)

  defp check_mooncore_dev_tools(conn, _opts) do
    if Mooncore.mooncore_dev_tools_enabled?() do
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

  # ── Static Assets ──

  get "/assets/mooncore.png" do
    png_path = Path.join(:code.priv_dir(:mooncore), "static/mooncore.png")

    case File.read(png_path) do
      {:ok, data} ->
        conn
        |> put_resp_content_type("image/png")
        |> put_resp_header("cache-control", "public, max-age=86400")
        |> send_resp(200, data)

      {:error, _} ->
        send_resp(conn, 404, "Not Found")
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

  # ── Dashboard API ──

  get "/api/dashboard" do
    # Memory
    mem = :erlang.memory()

    memory = %{
      total: mem[:total],
      processes: mem[:processes],
      binary: mem[:binary],
      ets: mem[:ets],
      atom: mem[:atom],
      code: mem[:code]
    }

    # Scheduler wall time
    :erlang.system_flag(:scheduler_wall_time, true)

    sched =
      case :erlang.statistics(:scheduler_wall_time) do
        :undefined ->
          []

        times ->
          times
          |> Enum.sort()
          |> Enum.map(fn {id, active, total} ->
            %{id: id, active: active, total: total}
          end)
      end

    # Reductions & runtime
    {reductions, _} = :erlang.statistics(:reductions)
    {runtime, _} = :erlang.statistics(:runtime)
    {wallclock, _} = :erlang.statistics(:wall_clock)

    # VM info
    vm = %{
      process_count: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      atom_count: :erlang.system_info(:atom_count),
      atom_limit: :erlang.system_info(:atom_limit),
      port_count: :erlang.system_info(:port_count),
      port_limit: :erlang.system_info(:port_limit),
      ets_count: length(:ets.all()),
      ets_limit: :erlang.system_info(:ets_limit),
      uptime_ms: wallclock,
      runtime_ms: runtime,
      reductions: reductions,
      otp_release: :erlang.system_info(:otp_release) |> to_string(),
      elixir_version: System.version(),
      schedulers: :erlang.system_info(:schedulers_online),
      logical_processors: :erlang.system_info(:logical_processors),
      system_architecture: :erlang.system_info(:system_architecture) |> to_string()
    }

    # Top processes by memory (top 20) — lightweight first pass
    top_procs =
      Process.list()
      |> Enum.map(fn pid ->
        case Process.info(pid, :memory) do
          {:memory, mem} -> {pid, mem}
          nil -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(&elem(&1, 1), :desc)
      |> Enum.take(20)
      |> Enum.map(fn {pid, _mem} ->
        case Process.info(pid, [
               :memory,
               :message_queue_len,
               :reductions,
               :current_function,
               :registered_name,
               :status
             ]) do
          nil ->
            nil

          info ->
            info = Map.new(info)

            %{
              pid: inspect(pid),
              name:
                case info[:registered_name] do
                  [] -> nil
                  name -> inspect(name)
                end,
              memory: info[:memory],
              mq_len: info[:message_queue_len],
              reductions: info[:reductions],
              status: to_string(info[:status]),
              current_fn:
                case info[:current_function] do
                  {m, f, a} -> "#{inspect(m)}.#{f}/#{a}"
                  _ -> nil
                end
            }
        end
      end)
      |> Enum.reject(&is_nil/1)

    # ETS tables
    ets_tables =
      :ets.all()
      |> Enum.map(fn tab ->
        try do
          ws = :erlang.system_info(:wordsize)

          %{
            name: inspect(:ets.info(tab, :name)),
            id: inspect(tab),
            size: :ets.info(tab, :size),
            memory: :ets.info(tab, :memory) * ws,
            type: to_string(:ets.info(tab, :type))
          }
        rescue
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.memory, :desc)

    # Applications
    apps =
      Application.started_applications()
      |> Enum.map(fn {name, desc, vsn} ->
        %{name: to_string(name), description: to_string(desc), version: to_string(vsn)}
      end)
      |> Enum.sort_by(& &1.name)

    data = %{
      memory: memory,
      schedulers: sched,
      vm: vm,
      top_processes: top_procs,
      ets_tables: ets_tables,
      applications: apps,
      timestamp: System.system_time(:millisecond)
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(data))
  end

  # ── Clients API ──

  get "/api/clients" do
    alias Mooncore.Endpoint.Socket.Clients

    data =
      try do
        state = Clients.list_all()

        groups =
          Enum.map(state, fn {group, channels} ->
            channel_list =
              Enum.map(channels, fn {channel, pids} ->
                %{
                  channel: channel,
                  members: Enum.map(pids, &inspect/1),
                  count: length(pids)
                }
              end)
              |> Enum.sort_by(& &1.channel)

            %{
              group: group,
              channels: channel_list,
              total: Enum.reduce(channel_list, 0, fn c, acc -> acc + c.count end)
            }
          end)
          |> Enum.sort_by(& &1.group)

        %{groups: groups}
      rescue
        _ -> %{groups: [], error: "Clients GenServer not running"}
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(data))
  end

  # ── Guides API ──

  get "/api/guides" do
    root = project_root()
    guides_dir = Path.join(root, "guides")

    items =
      case File.ls(guides_dir) do
        {:ok, entries} ->
          entries
          |> Enum.filter(&String.ends_with?(&1, ".md"))
          |> Enum.sort()
          |> Enum.map(fn name ->
            %{name: Path.rootname(name), file: name}
          end)

        {:error, _} ->
          []
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{guides: items}))
  end

  get "/api/guide" do
    name = conn.query_params["name"] || ""
    root = project_root()
    file = Path.join([root, "guides", name])

    if safe_path?(file, root) && String.ends_with?(name, ".md") do
      case File.read(file) do
        {:ok, content} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{name: Path.rootname(name), content: content}))

        {:error, _} ->
          json_error(conn, 404, "Guide not found")
      end
    else
      json_error(conn, 403, "Access denied")
    end
  end

  # ── File Browser API ──

  get "/api/files" do
    path = conn.query_params["path"] || "."
    root = project_root()
    full = Path.expand(path, root)

    if safe_path?(full, root) do
      case File.stat(full) do
        {:ok, %{type: :directory}} ->
          {:ok, entries} = File.ls(full)

          items =
            entries
            |> Enum.reject(&String.starts_with?(&1, "."))
            |> Enum.reject(&(&1 in ~w(_build deps node_modules .git)))
            |> Enum.sort()
            |> Enum.map(fn name ->
              fp = Path.join(full, name)
              rel = Path.relative_to(fp, root)

              case File.stat(fp) do
                {:ok, %{type: :directory}} -> %{name: name, path: rel, type: "dir"}
                {:ok, %{size: size}} -> %{name: name, path: rel, type: "file", size: size}
                _ -> %{name: name, path: rel, type: "file"}
              end
            end)
            |> Enum.sort_by(fn i -> {if(i.type == "dir", do: 0, else: 1), i.name} end)

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{path: Path.relative_to(full, root), items: items}))

        {:ok, _} ->
          json_error(conn, 400, "Not a directory")

        {:error, _} ->
          json_error(conn, 404, "Path not found")
      end
    else
      json_error(conn, 403, "Access denied")
    end
  end

  get "/api/file" do
    path = conn.query_params["path"] || ""
    root = project_root()
    full = Path.expand(path, root)

    if safe_path?(full, root) do
      case File.read(full) do
        {:ok, content} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{path: path, content: content}))

        {:error, _} ->
          json_error(conn, 404, "File not found")
      end
    else
      json_error(conn, 403, "Access denied")
    end
  end

  put "/api/file" do
    path = conn.body_params["path"] || ""
    content = conn.body_params["content"] || ""
    root = project_root()
    full = Path.expand(path, root)

    if safe_path?(full, root) do
      case File.write(full, content) do
        :ok ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{ok: true, path: path}))

        {:error, reason} ->
          json_error(conn, 500, "Write failed: #{reason}")
      end
    else
      json_error(conn, 403, "Access denied")
    end
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end

  defp project_root do
    case Mooncore.config(:project_root) do
      nil -> File.cwd!()
      root -> root
    end
  end

  defp safe_path?(full, root) do
    normalized = Path.expand(full)
    String.starts_with?(normalized, Path.expand(root))
  end

  defp json_error(conn, status, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: message}))
  end
end
