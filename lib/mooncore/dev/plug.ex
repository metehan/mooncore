defmodule Mooncore.Dev.Plug do
  import Bitwise

  @moduledoc """
  Development dashboard and MCP server plug.

  Runs on a dedicated port (default 4040), separate from the main app.
  Provides:
  - HTML dashboard with MCP tools, log viewer, and IEx console
  - Standard MCP protocol endpoint (JSON-RPC 2.0 over Streamable HTTP)
  - JSON API endpoints for MCP operations

  Only active when `config :mooncore, mooncore_dev_tools: true` AND `MOONCORE_DEV_SECRET` is set.
  Automatically started on the configured `mcp_port` (default: 4040).

  ## Configuration

      config :mooncore,
        mooncore_dev_tools: true,
        mcp_port: 4040,                # default
        dev_tools_allowed_ips: [        # optional IP allowlist
          "127.0.0.1",
          "::1",
          "10.0.0.0/8"
        ],
        oauth_redirect_uris: [          # optional extra OAuth redirect URI allowlist
          "https://myapp.example.com/callback"
        ],
        oauth_access_token_ttl_seconds: 1_209_600 # default: 14 days
  """

  use Plug.Router

  @default_oauth_access_token_ttl_seconds 14 * 24 * 60 * 60

  plug(:check_mooncore_dev_tools)
  plug(:check_dev_ip)

  plug(Plug.Parsers,
    parsers: [:urlencoded, {:json, json_decoder: Jason}],
    pass: ["application/json", "application/x-www-form-urlencoded"]
  )

  plug(:check_dev_auth)

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

  # ── Dev Tools IP Allowlist ──

  @doc """
  IP allowlist check for dev tools.

  If `dev_tools_allowed_ips` is configured, only requests from
  allowed IPs pass through. CIDR ranges (e.g. `"10.0.0.0/8"`) are supported.
  If the config is `nil` or empty, all IPs are allowed (backwards compatible).
  """
  def check_dev_ip(conn, _opts) do
    allowed_ips = Mooncore.dev_tools_allowed_ips()

    if is_nil(allowed_ips) or allowed_ips == [] do
      conn
    else
      client_ip_str = client_ip(conn)

      if ip_allowed?(client_ip_str, allowed_ips) do
        conn
      else
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, Jason.encode!(%{error: "Forbidden"}))
        |> halt()
      end
    end
  end

  defp client_ip(conn) do
    conn
    |> Plug.Conn.get_req_header("x-forwarded-for")
    |> List.first()
    |> case do
      nil -> remote_ip(conn)
      ip when is_binary(ip) -> ip |> String.split(",") |> List.first() |> String.trim()
    end
  end

  defp remote_ip(conn) do
    conn.remote_ip |> Tuple.to_list() |> Enum.join(".")
  end

  defp ip_allowed?(client_ip, allowed_ips) do
    client = ip_to_tuple(client_ip)
    Enum.any?(allowed_ips, &match_cidr?(client, &1))
  end

  defp ip_to_tuple(ip) when is_binary(ip) do
    if String.contains?(ip, ":") do
      # IPv6
      ip
      |> String.split(":")
      |> Enum.map(&String.pad_leading(String.trim(&1), 4, ?0))
      |> Enum.join(":")
      |> then(&:inet.parse_ipv6_address/1)
      |> case do
        {:ok, addr} -> addr
        _ -> nil
      end
    else
      # IPv4
      ip
      |> String.split(".")
      |> Enum.map(&String.to_integer/1)
      |> List.to_tuple()
    end
  end

  defp ip_to_tuple(_), do: nil

  defp match_cidr?(client_ip, cidr_entry) when is_tuple(client_ip) and is_binary(cidr_entry) do
    if String.contains?(cidr_entry, "/") do
      [prefix, bits_s] = String.split(cidr_entry, "/")
      bits = String.to_integer(bits_s)
      target = ip_to_tuple(prefix)
      match_cidr_bits(client_ip, target, bits)
    else
      ip_to_tuple(cidr_entry) == client_ip
    end
  end

  defp match_cidr_bits(client_ip, target, bits) when tuple_size(client_ip) == 4 do
    # IPv4
    mask = if bits == 0, do: 0, else: (1 <<< 32) - 1 - ((1 <<< (32 - bits)) - 1)
    client_int = ip_to_int(client_ip)
    target_int = ip_to_int(target)
    (client_int &&& mask) == (target_int &&& mask)
  end

  defp match_cidr_bits(client_ip, target, bits) when tuple_size(client_ip) == 8 do
    # IPv6
    mask = if bits == 0, do: 0, else: (1 <<< 128) - 1 - ((1 <<< (128 - bits)) - 1)
    client_int = ip_to_int_v6(client_ip)
    target_int = ip_to_int_v6(target)
    (client_int &&& mask) == (target_int &&& mask)
  end

  defp match_cidr_bits(_, _, _), do: false

  defp ip_to_int({a, b, c, d}) do
    a <<< 24 ||| b <<< 16 ||| c <<< 8 ||| d
  end

  defp ip_to_int_v6({a, b, c, d, e, f, g, h}) do
    Enum.reduce({a, b, c, d, e, f, g, h}, 0, fn seg, acc ->
      acc <<< 16 ||| seg
    end)
  end

  # ── Standard MCP Protocol (JSON-RPC 2.0, Streamable HTTP) ──

  post "/mcp" do
    body = conn.body_params

    case body do
      # Batch request (array) — Plug stores top-level JSON arrays as %{"_json" => [...]}
      %{"_json" => requests} when is_list(requests) ->
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

  @static_dir Path.join(__DIR__, "static")

  get "/assets/*path" do
    file = Path.join([@static_dir | path])

    if String.starts_with?(Path.expand(file), @static_dir) do
      case File.read(file) do
        {:ok, data} ->
          mime = MIME.from_path(file)

          conn
          |> put_resp_content_type(mime)
          |> put_resp_header("cache-control", "no-cache")
          |> send_resp(200, data)

        {:error, _} ->
          send_resp(conn, 404, "Not Found")
      end
    else
      send_resp(conn, 403, "Forbidden")
    end
  end

  get "/favicon.ico" do
    file = Path.join(@static_dir, "favicon.ico")

    case File.read(file) do
      {:ok, data} ->
        conn
        |> put_resp_content_type("image/x-icon")
        |> put_resp_header("cache-control", "public, max-age=86400")
        |> send_resp(200, data)

      {:error, _} ->
        send_resp(conn, 404, "Not Found")
    end
  end

  # ── HTML Dashboard ──

  get "/" do
    base =
      case conn.script_name do
        [] -> ""
        parts -> "/" <> Enum.join(parts, "/")
      end

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, Mooncore.Dev.Page.render(base))
  end

  # ── Dev Auth Login ──

  @dev_session_expiry_options %{
    "1h" => 3600,
    "8h" => 28800,
    "1d" => 86_400,
    "1w" => 604_800,
    "1m" => 2_592_000
  }

  post "/dev/login" do
    secret = System.get_env("MOONCORE_DEV_SECRET") || ""
    password = conn.body_params["password"] || ""
    expiry_label = conn.body_params["expiry"] || "1w"
    expiry_seconds = Map.get(@dev_session_expiry_options, expiry_label, 604_800)

    if byte_size(secret) > 0 and byte_size(password) > 0 and
         Plug.Crypto.secure_compare(password, secret) do
      now = System.system_time(:second)
      expiry_ts = now + expiry_seconds
      token = dev_session_token(secret, expiry_ts)

      # Store expiry alongside token so check_dev_auth can verify it
      conn
      |> put_resp_cookie("mooncore_dev", token,
        http_only: true,
        same_site: "Strict",
        max_age: expiry_seconds
      )
      |> put_resp_cookie("mooncore_dev_exp", Integer.to_string(expiry_ts),
        http_only: false,
        same_site: "Strict",
        max_age: expiry_seconds
      )
      |> put_resp_content_type("application/json")
      |> send_resp(
        200,
        Jason.encode!(%{
          ok: true,
          expires_in: expiry_seconds
        })
      )
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(401, Jason.encode!(%{error: "invalid password"}))
    end
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

  post "/api/ets/insert" do
    table_id = conn.body_params["table"]
    term_str = conn.body_params["term"] || ""

    result =
      try do
        tab = decode_ets_table_id(table_id)

        {term, _bindings} = Code.eval_string(term_str)
        :ets.insert(tab, term)
        %{ok: true}
      rescue
        e -> %{ok: false, error: Exception.message(e)}
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(result))
  end

  post "/api/ets/delete" do
    table_id = conn.body_params["table"]
    key_str = conn.body_params["key"] || ""

    result =
      try do
        tab = decode_ets_table_id(table_id)

        {key, _bindings} = Code.eval_string(key_str)
        :ets.delete(tab, key)
        %{ok: true}
      rescue
        e -> %{ok: false, error: Exception.message(e)}
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(result))
  end

  get "/api/ets/rows" do
    table_id = conn.query_params["table"]
    filter = String.trim(conn.query_params["filter"] || "")

    page =
      case Integer.parse(conn.query_params["page"] || "1") do
        {n, _} -> max(n, 1)
        :error -> 1
      end

    limit =
      case Integer.parse(conn.query_params["limit"] || "50") do
        {n, _} -> n |> min(200) |> max(1)
        :error -> 50
      end

    result =
      try do
        tab = decode_ets_table_id(table_id)

        case :ets.info(tab) do
          :undefined ->
            %{ok: false, error: "Table no longer exists"}

          info ->
            protection = info[:protection]

            if protection == :private do
              %{ok: false, error: "Table is private and cannot be inspected from devtools"}
            else
              {rows, total_matching} = fetch_ets_rows(tab, filter, page, limit)
              total_pages = max(div(max(total_matching - 1, 0), limit) + 1, 1)

              %{
                ok: true,
                rows: rows,
                protection: to_string(protection),
                filter: filter,
                page: page,
                limit: limit,
                total_matching: total_matching,
                total_pages: total_pages,
                has_prev: page > 1,
                has_next: page < total_pages
              }
            end
        end
      rescue
        _ ->
          %{ok: false, error: "Table could not be inspected"}
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(result))
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
            id: encode_ets_table_id(tab),
            size: :ets.info(tab, :size),
            memory: :ets.info(tab, :memory) * ws,
            type: to_string(:ets.info(tab, :type)),
            protection: to_string(:ets.info(tab, :protection))
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

    topology = supervisor_topology_snapshot()

    # Dev tools allowlist info (frontend uses this to show warnings)
    allowed_ips = Mooncore.dev_tools_allowed_ips()
    allowlist_set = not (is_nil(allowed_ips) or allowed_ips == [])

    data = %{
      memory: memory,
      schedulers: sched,
      vm: vm,
      top_processes: top_procs,
      ets_tables: ets_tables,
      applications: apps,
      topology: topology,
      dev_tools_allowed_ips: allowed_ips,
      dev_tools_allowlist_set: allowlist_set,
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
        pools = Mooncore.config(:pools, [:default])

        groups =
          Enum.flat_map(pools, fn pool ->
            Clients.list_all(pool)
            |> Enum.map(fn {group, channels} ->
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
                pool: pool,
                group: group,
                channels: channel_list,
                total: Enum.reduce(channel_list, 0, fn c, acc -> acc + c.count end)
              }
            end)
          end)
          |> Enum.sort_by(&{&1.group, &1.pool})

        %{groups: groups}
      rescue
        _ -> %{groups: [], error: "Clients GenServer not running"}
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(data))
  end

  # ── Socket Logs API ──

  get "/api/socket-logs" do
    conn = fetch_query_params(conn)
    qp = conn.query_params

    parse_int = fn s ->
      case s && Integer.parse(s) do
        {n, _} -> n
        _ -> nil
      end
    end

    opts =
      %{
        "limit" => parse_int.(qp["limit"]),
        "user" => qp["user"],
        "channel" => qp["channel"],
        "direction" => qp["direction"],
        "since_id" => parse_int.(qp["since_id"])
      }
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()

    data =
      try do
        logs = Mooncore.MCP.Server.read_socket_logs(opts)
        %{logs: logs}
      rescue
        _ -> %{logs: [], error: "Could not read socket logs"}
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

  # ── Custom Pages / Devtools API ──

  get "/api/devtools/pages" do
    pages = Mooncore.Dev.Devtools.get_pages()
    # Already normalized to JSON-safe maps in Devtools
    pages_list = Enum.map(pages, fn {name, defn} -> %{name: name, definition: defn} end)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{pages: pages_list}))
  end

  get "/api/devtools/page" do
    page_name = conn.query_params["name"] || ""

    case Mooncore.Dev.Devtools.get_page(page_name) do
      {:ok, defn} ->
        # Already JSON-safe from Devtools.normalize_page_def
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(defn))

      {:error, :not_found} ->
        json_error(conn, 404, "Page not found: #{page_name}")
    end
  end

  get "/api/devtools/data" do
    source_type = conn.query_params["type"] || ""
    source_key = conn.query_params["key"] || ""

    source =
      case source_type do
        "metric" -> {:metric, source_key}
        "collection" -> {:collection, source_key}
        "timeseries" -> {:timeseries, source_key}
        _ -> nil
      end

    if source do
      case Mooncore.Dev.Devtools.get_data(source) do
        {:ok, data} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{data: data}))

        {:error, :not_found} ->
          json_error(conn, 404, "Data not found")
      end
    else
      json_error(conn, 400, "Invalid source type")
    end
  end

  post "/api/devtools/eval" do
    if not Mooncore.mooncore_dev_tools_enabled?() do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(503, Jason.encode!(%{ok: false, error: "Dev tools not enabled"}))
    else
      code = conn.body_params["code"] || ""
      _widget_id = conn.body_params["widget_id"]
      item_json = conn.body_params["item"]

      result =
        try do
          bindings =
            if item_json do
              item = Jason.decode!(item_json)
              [{:item, item}]
            else
              []
            end

          {result, _} = Code.eval_string(code, bindings)
          %{ok: true, result: inspect(result)}
        rescue
          e -> %{ok: false, error: Exception.message(e)}
        end

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(result))
    end
  end

  # ── OAuth 2.0 Authorization Server (MCP 2025-03-26, RFC 8414 / RFC 7591 / RFC 6749) ──

  get "/.well-known/oauth-protected-resource" do
    base = oauth_server_base(conn)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{resource: base, authorization_servers: [base]}))
  end

  get "/.well-known/oauth-authorization-server" do
    base = oauth_server_base(conn)

    meta = %{
      issuer: base,
      authorization_endpoint: "#{base}/oauth/authorize",
      token_endpoint: "#{base}/oauth/token",
      registration_endpoint: "#{base}/oauth/register",
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none"],
      scopes_supported: ["mcp"]
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(meta))
  end

  # Dynamic Client Registration (RFC 7591) — no persistent storage needed for dev tools
  post "/oauth/register" do
    redirect_uris = conn.body_params["redirect_uris"] || []
    client_name = conn.body_params["client_name"] || "MCP Client"

    client_id =
      :crypto.hash(:sha256, :erlang.term_to_binary({redirect_uris, client_name}))
      |> Base.url_encode64(padding: false)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      201,
      Jason.encode!(%{
        client_id: client_id,
        client_name: client_name,
        redirect_uris: redirect_uris,
        grant_types: ["authorization_code"],
        response_types: ["code"],
        token_endpoint_auth_method: "none"
      })
    )
  end

  get "/oauth/authorize" do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, oauth_authorize_page(conn.query_params))
  end

  post "/oauth/authorize" do
    secret = System.get_env("MOONCORE_DEV_SECRET") || ""
    password = conn.body_params["password"] || ""
    redirect_uri = conn.body_params["redirect_uri"] || ""
    state = conn.body_params["state"] || ""
    code_challenge = conn.body_params["code_challenge"] || ""

    # Only allow redirect URIs that point to localhost, vscode callback, or the configured allowlist
    allowed_uris = Mooncore.config(:oauth_redirect_uris, [])

    safe_redirect? =
      Enum.member?(allowed_uris, redirect_uri) or
        case URI.parse(redirect_uri) do
          %URI{scheme: "http", host: h} when h in ["localhost", "127.0.0.1", "::1"] -> true
          %URI{scheme: "https"} -> true
          %URI{scheme: "vscode", host: "vscode.dev"} -> true
          _ -> false
        end

    if byte_size(secret) > 0 and byte_size(password) > 0 and
         Plug.Crypto.secure_compare(password, secret) and safe_redirect? do
      code = oauth_issue_auth_code(secret, code_challenge)
      sep = if String.contains?(redirect_uri, "?"), do: "&", else: "?"

      location =
        "#{redirect_uri}#{sep}code=#{URI.encode_www_form(code)}&state=#{URI.encode_www_form(state)}"

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{location: location}))
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(401, Jason.encode!(%{error: "invalid_request"}))
    end
  end

  post "/oauth/token" do
    grant_type = conn.body_params["grant_type"] || ""
    code = conn.body_params["code"] || ""
    code_verifier = conn.body_params["code_verifier"]

    if grant_type != "authorization_code" do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{error: "unsupported_grant_type"}))
    else
      secret = System.get_env("MOONCORE_DEV_SECRET") || ""

      case oauth_verify_auth_code(secret, code, code_verifier) do
        {:ok, code_expiry} ->
          {access_token, token_expiry} = oauth_issue_access_token(secret, code_expiry)
          expires_in = token_expiry - System.system_time(:second)

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            200,
            Jason.encode!(%{
              access_token: access_token,
              token_type: "Bearer",
              expires_in: expires_in
            })
          )

        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(400, Jason.encode!(%{error: reason}))
      end
    end
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end

  defp check_dev_auth(conn, _opts) do
    # OAuth discovery and token endpoints are public — they handle their own auth
    oauth_path? =
      String.starts_with?(conn.request_path, "/.well-known/") or
        String.starts_with?(conn.request_path, "/oauth/")

    if oauth_path? do
      conn
    else
      secret = System.get_env("MOONCORE_DEV_SECRET")

      if is_binary(secret) and byte_size(secret) > 0 do
        conn = fetch_cookies(conn)
        auth_header = get_req_header(conn, "authorization") |> List.first()
        header_val = get_req_header(conn, "x-dev-secret") |> List.first()

        authed =
          cond do
            # x-dev-secret: <raw secret> — for scripts and local automation
            is_binary(header_val) ->
              Plug.Crypto.secure_compare(header_val, secret)

            # OAuth Bearer token — for VS Code MCP and API clients
            is_binary(auth_header) and String.starts_with?(auth_header, "Bearer ") ->
              bearer = String.slice(auth_header, 7, String.length(auth_header))
              oauth_verify_access_token(secret, bearer)

            # Cookie — for browser dashboard
            true ->
              cookie_token = conn.cookies["mooncore_dev"]
              cookie_exp = conn.cookies["mooncore_dev_exp"]

              exp_ts =
                case cookie_exp do
                  s when is_binary(s) ->
                    case Integer.parse(s) do
                      {ts, ""} -> ts
                      _ -> nil
                    end

                  _ ->
                    nil
                end

              expected_token = exp_ts && dev_session_token(secret, exp_ts)

              is_binary(cookie_token) and is_binary(expected_token) and
                Plug.Crypto.secure_compare(cookie_token, expected_token) and
                System.system_time(:second) <= exp_ts
          end

        if authed or conn.request_path == "/dev/login" do
          conn
        else
          resource_meta = "#{oauth_server_base(conn)}/.well-known/oauth-protected-resource"
          www_auth = "Bearer realm=\"Mooncore DevTools\", resource_metadata=\"#{resource_meta}\""

          if String.starts_with?(conn.request_path, "/api/") or conn.request_path == "/mcp" do
            conn
            |> put_resp_header("www-authenticate", www_auth)
            |> put_resp_content_type("application/json")
            |> send_resp(
              401,
              Jason.encode!(%{
                error: "unauthorized",
                message: "Authenticate via OAuth (MCP), x-dev-secret header, or browser cookie."
              })
            )
            |> halt()
          else
            conn
            |> put_resp_content_type("text/html")
            |> send_resp(200, dev_login_page())
            |> halt()
          end
        end
      else
        # No secret configured — reject API/protocol endpoints
        if conn.request_path == "/mcp" or String.starts_with?(conn.request_path, "/api/") do
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            401,
            Jason.encode!(%{
              error: "unauthorized",
              message:
                "MOONCORE_DEV_SECRET is not configured — dev tools authentication is required."
            })
          )
          |> halt()
        else
          conn
        end
      end
    end
  end

  # ── Dev Session Token ──
  # Expiry-bound HMAC token used for browser cookie auth
  defp dev_session_token(secret, expiry_ts) do
    :crypto.mac(:hmac, :sha256, secret <> Integer.to_string(expiry_ts), "mooncore-dev-session")
    |> Base.url_encode64(padding: false)
  end

  defp dev_login_page do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Mooncore DevTools</title>
      <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { background: #0f172a; color: #e2e8f0; font-family: system-ui, sans-serif;
               display: flex; align-items: center; justify-content: center; min-height: 100vh; }
        .card { background: #1e293b; border: 1px solid #334155; border-radius: 12px;
                padding: 2rem; width: 100%; max-width: 420px; }
        h1 { font-size: 1.2rem; font-weight: 600; margin-bottom: 0.25rem; }
        p { font-size: 0.85rem; color: #94a3b8; margin-bottom: 1.5rem; }
        code { background: #0f172a; padding: 1px 5px; border-radius: 4px; font-size: 0.8rem; }
        .field { margin-bottom: 0.75rem; }
        label { display: block; font-size: 0.8rem; color: #94a3b8; margin-bottom: 0.35rem; }
        select, input { width: 100%; background: #0f172a; border: 1px solid #334155; border-radius: 6px;
                padding: 0.6rem 0.75rem; color: #e2e8f0; font-size: 0.9rem; outline: none; }
        select:focus, input:focus { border-color: #6366f1; }
        button { margin-top: 0.75rem; width: 100%; background: #6366f1; color: white;
                 border: none; border-radius: 6px; padding: 0.65rem; font-size: 0.95rem;
                 cursor: pointer; font-weight: 500; }
        button:hover { background: #4f46e5; }
        .error { margin-top: 0.5rem; color: #f87171; font-size: 0.85rem; display: none; }
      </style>
    </head>
    <body>
      <div class="card">
        <h1>Mooncore DevTools</h1>
        <p>Enter the <code>MOONCORE_DEV_SECRET</code> to continue.</p>

        <div class="field">
          <label for="pw">Secret</label>
          <input type="password" id="pw" placeholder="Enter secret" autofocus>
        </div>

        <div class="field">
          <label for="expiry">Token expiry</label>
          <select id="expiry">
            <option value="1h">1 hour</option>
            <option value="8h">8 hour</option>
            <option value="1d">1 day</option>
            <option value="1w" selected>1 week</option>
            <option value="1m">1 month</option>
          </select>
        </div>

        <button onclick="login()">Unlock</button>
        <div class="error" id="err">Incorrect secret.</div>
      </div>

      <script>
        document.getElementById('pw').addEventListener('keydown', e => {
          if (e.key === 'Enter') login();
        });
        async function login() {
          const pw = document.getElementById('pw').value;
          const expiry = document.getElementById('expiry').value;
          const res = await fetch('/dev/login', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({password: pw, expiry: expiry})
          });
          const data = await res.json();
          if (res.ok) {
            // Redirect to dashboard after successful login
            window.location.href = '/';
          } else {
            document.getElementById('err').style.display = 'block';
            document.getElementById('pw').select();
          }
        }
      </script>
    </body>
    </html>
    """
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

  defp supervisor_topology_snapshot do
    supervisors = registered_supervisors()

    child_supervisor_pids =
      supervisors
      |> Enum.flat_map(fn {_name, pid} -> direct_child_supervisor_pids(pid) end)
      |> MapSet.new()

    roots =
      supervisors
      |> Enum.reject(fn {_name, pid} -> MapSet.member?(child_supervisor_pids, pid) end)
      |> Enum.map(fn {name, pid} -> build_supervisor_node(pid, name, MapSet.new()) end)

    if roots == [] and supervisors != [] do
      %{
        roots:
          Enum.map(supervisors, fn {name, pid} ->
            build_supervisor_node(pid, name, MapSet.new())
          end),
        registered_processes: length(Process.registered()),
        supervisor_count: length(supervisors),
        root_count: length(supervisors)
      }
    else
      %{
        roots: roots,
        registered_processes: length(Process.registered()),
        supervisor_count: length(supervisors),
        root_count: length(roots)
      }
    end
  end

  defp registered_supervisors do
    Process.registered()
    |> Enum.map(fn name -> {name, Process.whereis(name)} end)
    |> Enum.filter(fn {_name, pid} -> is_pid(pid) end)
    |> Enum.filter(fn {_name, pid} -> otp_module(pid) == :supervisor end)
  end

  defp direct_child_supervisor_pids(pid) do
    pid
    |> safe_which_children()
    |> Enum.flat_map(fn {_id, child_pid, type, _modules} ->
      if type == :supervisor and is_pid(child_pid), do: [child_pid], else: []
    end)
  end

  defp build_supervisor_node(pid, registered_name, visited) do
    pid_key = inspect(pid)

    if MapSet.member?(visited, pid_key) do
      %{
        id: registered_name && inspect(registered_name),
        label: node_label(registered_name, pid),
        pid: pid_key,
        kind: "supervisor",
        cycle: true,
        children: []
      }
    else
      next_visited = MapSet.put(visited, pid_key)
      counts = safe_count_children(pid)

      children =
        pid
        |> safe_which_children()
        |> Enum.map(fn {id, child_pid, type, modules} ->
          build_child_node(id, child_pid, type, modules, next_visited)
        end)

      %{
        id: registered_name && inspect(registered_name),
        label: node_label(registered_name, pid),
        pid: pid_key,
        kind: "supervisor",
        restart_strategy: safe_supervisor_strategy(pid),
        counts: counts,
        children: children
      }
    end
  end

  defp build_child_node(id, child_pid, type, modules, visited) do
    cond do
      type == :supervisor and is_pid(child_pid) ->
        build_supervisor_node(child_pid, registered_name(child_pid) || id, visited)

      is_pid(child_pid) ->
        worker_node(id, child_pid, modules)

      child_pid == :restarting ->
        %{
          id: inspect(id),
          label: inspect(id),
          pid: "restarting",
          kind: worker_kind_from_modules(modules),
          modules: format_modules(modules),
          status: "restarting"
        }

      true ->
        %{
          id: inspect(id),
          label: inspect(id),
          pid: nil,
          kind: worker_kind_from_modules(modules),
          modules: format_modules(modules),
          status: "not_started"
        }
    end
  end

  defp worker_node(id, pid, modules) do
    %{
      id: inspect(id),
      label: node_label(registered_name(pid) || id, pid),
      pid: inspect(pid),
      kind: worker_kind(pid, modules),
      modules: format_modules(modules),
      status: process_status(pid),
      message_queue_len: process_message_queue_len(pid),
      current_function: process_current_function(pid),
      state_preview: safe_state_preview(pid)
    }
  end

  defp node_label(nil, pid), do: inspect(pid)
  defp node_label(name, _pid), do: inspect(name)

  defp registered_name(pid) do
    case Process.info(pid, :registered_name) do
      {:registered_name, []} -> nil
      {:registered_name, name} -> name
      _ -> nil
    end
  end

  defp otp_module(pid) do
    case safe_sys_status(pid) do
      {:status, ^pid, {:module, module}, _} -> module
      _ -> nil
    end
  end

  defp worker_kind(pid, modules) do
    case otp_module(pid) do
      :gen_server -> "gen_server"
      :gen_statem -> "gen_statem"
      :gen_event -> "gen_event"
      :supervisor -> "supervisor"
      _ -> worker_kind_from_modules(modules)
    end
  end

  defp worker_kind_from_modules(modules) do
    case modules do
      [:supervisor] -> "supervisor"
      [module] when is_atom(module) -> inspect(module)
      _ -> "worker"
    end
  end

  defp format_modules(:dynamic), do: "dynamic"
  defp format_modules(modules) when is_list(modules), do: Enum.map_join(modules, ", ", &inspect/1)
  defp format_modules(_), do: nil

  defp safe_which_children(pid) do
    Supervisor.which_children(pid)
  catch
    :exit, _ -> []
  end

  defp safe_count_children(pid) do
    pid
    |> Supervisor.count_children()
    |> Enum.into(%{}, fn {key, value} -> {to_string(key), value} end)
  catch
    :exit, _ -> %{}
  end

  defp safe_supervisor_strategy(pid) do
    case safe_sys_status(pid) do
      {:status, ^pid, {:module, :supervisor}, [_pdict, _sys_state, _parent, _debug, misc]} ->
        misc
        |> extract_supervisor_flags()
        |> Map.get(:strategy)
        |> case do
          nil -> nil
          strategy -> to_string(strategy)
        end

      _ ->
        nil
    end
  end

  defp extract_supervisor_flags({flags, _children}) when is_map(flags), do: flags

  defp extract_supervisor_flags({{strategy, intensity, period}, _children}),
    do: %{strategy: strategy, intensity: intensity, period: period}

  defp extract_supervisor_flags(_), do: %{}

  defp safe_sys_status(pid) do
    if otp_behavior?(pid) do
      try do
        :sys.get_status(pid, 50)
      catch
        :exit, _ -> nil
      end
    end
  end

  defp otp_behavior?(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dict} ->
        case List.keyfind(dict, :"$initial_call", 0) do
          {_, {:supervisor, _, _}} ->
            true

          {_, {:gen_server, _, _}} ->
            true

          {_, {:gen_statem, _, _}} ->
            true

          {_, {:gen_event, _, _}} ->
            true

          {_, {mod, _, _}} ->
            mod_str = Atom.to_string(mod)

            String.contains?(mod_str, "GenServer") or
              String.contains?(mod_str, "Supervisor") or
              String.contains?(mod_str, "GenStatem") or
              String.contains?(mod_str, "GenEvent")

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp safe_state_preview(pid) do
    case otp_module(pid) do
      module when module in [:gen_server, :gen_statem, :gen_event] ->
        try do
          pid
          |> :sys.get_state(50)
          |> inspect(pretty: true, limit: 8, printable_limit: 400)
        catch
          :exit, _ -> nil
        end

      _ ->
        nil
    end
  end

  defp process_status(pid) do
    case Process.info(pid, :status) do
      {:status, status} -> to_string(status)
      _ -> nil
    end
  end

  defp process_message_queue_len(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, len} -> len
      _ -> 0
    end
  end

  defp fetch_ets_rows(tab, filter, page, limit) do
    offset = (page - 1) * limit
    normalized_filter = String.downcase(filter)

    :ets.safe_fixtable(tab, true)

    try do
      tab
      |> :ets.first()
      |> scan_ets_rows(tab, normalized_filter, offset, limit, 0, [])
    after
      :ets.safe_fixtable(tab, false)
    end
  end

  defp scan_ets_rows(:"$end_of_table", _tab, _filter, _offset, _limit, total_matching, acc) do
    {Enum.reverse(acc), total_matching}
  end

  defp scan_ets_rows(key, tab, filter, offset, limit, total_matching, acc) do
    objects = :ets.lookup(tab, key)

    {next_total, next_acc} =
      Enum.reduce(objects, {total_matching, acc}, fn row, {count, rows} ->
        row_text = inspect(row, pretty: false, limit: 20, printable_limit: 2_000)

        if filter == "" or String.contains?(String.downcase(row_text), filter) do
          next_count = count + 1

          cond do
            next_count <= offset ->
              {next_count, rows}

            length(rows) >= limit ->
              {next_count, rows}

            true ->
              built_row = %{
                index: next_count,
                preview: inspect(row, pretty: true, limit: 6, printable_limit: 220),
                term: serialize_term(row),
                bytes: :erts_debug.flat_size(row) * :erlang.system_info(:wordsize)
              }

              {next_count, [built_row | rows]}
          end
        else
          {count, rows}
        end
      end)

    scan_ets_rows(:ets.next(tab, key), tab, filter, offset, limit, next_total, next_acc)
  end

  defp serialize_term(term, depth \\ 0)

  defp serialize_term(term, depth) when depth >= 4 do
    %{kind: "inspect", value: inspect(term, pretty: true, limit: 6, printable_limit: 240)}
  end

  defp serialize_term(term, _depth) when is_nil(term) or is_boolean(term) or is_number(term) do
    %{kind: "scalar", value: term}
  end

  defp serialize_term(term, _depth) when is_binary(term) do
    %{
      kind: "binary",
      value: binary_preview(term),
      length: byte_size(term),
      utf8: String.valid?(term)
    }
  end

  defp serialize_term(term, _depth) when is_atom(term) do
    %{kind: "atom", value: inspect(term)}
  end

  defp serialize_term(term, _depth)
       when is_pid(term) or is_port(term) or is_reference(term) or is_function(term) do
    %{kind: "inspect", value: inspect(term)}
  end

  defp serialize_term(term, depth) when is_tuple(term) do
    items = term |> Tuple.to_list() |> Enum.take(25) |> Enum.map(&serialize_term(&1, depth + 1))

    %{
      kind: "tuple",
      size: tuple_size(term),
      truncated: tuple_size(term) > 25,
      items: items
    }
  end

  defp serialize_term(term, depth) when is_list(term) do
    items = term |> Enum.take(25) |> Enum.map(&serialize_term(&1, depth + 1))

    %{
      kind: "list",
      size: length(term),
      truncated: length(term) > 25,
      items: items
    }
  end

  defp serialize_term(term, depth) when is_map(term) do
    entries =
      term
      |> Enum.take(25)
      |> Enum.map(fn {key, value} ->
        %{
          key: serialize_term(key, depth + 1),
          value: serialize_term(value, depth + 1)
        }
      end)

    %{
      kind: "map",
      size: map_size(term),
      truncated: map_size(term) > 25,
      entries: entries
    }
  end

  defp serialize_term(term, _depth) do
    %{kind: "inspect", value: inspect(term, pretty: true, limit: 6, printable_limit: 240)}
  end

  defp binary_preview(term) do
    if String.valid?(term) do
      String.slice(term, 0, 1_000)
    else
      inspect(term, pretty: true, limit: 6, printable_limit: 240)
    end
  end

  defp encode_ets_table_id(tab) do
    tab
    |> :erlang.term_to_binary()
    |> Base.url_encode64(padding: false)
  end

  defp decode_ets_table_id(encoded) when is_binary(encoded) do
    encoded
    |> Base.url_decode64!(padding: false)
    |> :erlang.binary_to_term([:safe])
  end

  defp process_current_function(pid) do
    case Process.info(pid, :current_function) do
      {:current_function, {mod, fun, arity}} -> "#{inspect(mod)}.#{fun}/#{arity}"
      _ -> nil
    end
  end

  # ── OAuth 2.0 Helpers ──

  defp oauth_server_base(conn) do
    %URI{scheme: s, host: h, port: p} = conn |> request_url() |> URI.parse()
    default_port = if s == "https", do: 443, else: 80
    if p == default_port, do: "#{s}://#{h}", else: "#{s}://#{h}:#{p}"
  end

  # Auth code format: "#{expiry}.#{code_challenge}.#{hmac}"
  # code_challenge and hmac are base64url (no dots), expiry is an integer — safe to split on "."
  defp oauth_issue_auth_code(secret, code_challenge) do
    expiry = System.system_time(:second) + 300
    payload = "#{expiry}.#{code_challenge}"

    hmac =
      :crypto.mac(:hmac, :sha256, secret, "mooncore-oauth-code.#{payload}")
      |> Base.url_encode64(padding: false)

    "#{payload}.#{hmac}"
  end

  defp oauth_verify_auth_code(secret, code, code_verifier) do
    case String.split(code, ".", parts: 3) do
      [expiry_str, code_challenge, hmac] ->
        expiry = String.to_integer(expiry_str)
        now = System.system_time(:second)
        payload = "#{expiry_str}.#{code_challenge}"

        expected_hmac =
          :crypto.mac(:hmac, :sha256, secret, "mooncore-oauth-code.#{payload}")
          |> Base.url_encode64(padding: false)

        cond do
          not Plug.Crypto.secure_compare(hmac, expected_hmac) ->
            {:error, "invalid_grant"}

          now > expiry ->
            {:error, "invalid_grant"}

          is_binary(code_verifier) ->
            expected_challenge =
              :crypto.hash(:sha256, code_verifier)
              |> Base.url_encode64(padding: false)

            if Plug.Crypto.secure_compare(expected_challenge, code_challenge),
              do: {:ok, expiry},
              else: {:error, "invalid_grant"}

          true ->
            {:ok, expiry}
        end

      _ ->
        {:error, "invalid_grant"}
    end
  end

  # Access token format: "#{expiry}.#{hmac}"
  defp oauth_issue_access_token(secret, _code_expiry) do
    expiry = System.system_time(:second) + oauth_access_token_ttl_seconds()

    hmac =
      :crypto.mac(:hmac, :sha256, secret, "mooncore-oauth-token.#{expiry}")
      |> Base.url_encode64(padding: false)

    {"#{expiry}.#{hmac}", expiry}
  end

  defp oauth_access_token_ttl_seconds do
    case Mooncore.config(
           :oauth_access_token_ttl_seconds,
           @default_oauth_access_token_ttl_seconds
         ) do
      ttl when is_integer(ttl) and ttl > 0 -> ttl
      _invalid_ttl -> @default_oauth_access_token_ttl_seconds
    end
  end

  defp oauth_verify_access_token(secret, token) do
    case String.split(token, ".", parts: 2) do
      [expiry_str, hmac] ->
        with {expiry, ""} <- Integer.parse(expiry_str),
             expected_hmac =
               :crypto.mac(:hmac, :sha256, secret, "mooncore-oauth-token.#{expiry_str}")
               |> Base.url_encode64(padding: false),
             true <- Plug.Crypto.secure_compare(hmac, expected_hmac),
             true <- System.system_time(:second) <= expiry do
          true
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  defp oauth_authorize_page(params) do
    redirect_uri = params["redirect_uri"] || ""
    state = params["state"] || ""
    client_id = params["client_id"] || ""
    code_challenge = params["code_challenge"] || ""
    code_challenge_method = params["code_challenge_method"] || "S256"
    scope = params["scope"] || "mcp"

    client_display =
      case URI.parse(redirect_uri) do
        %URI{host: h} when is_binary(h) and h != "" -> h
        _ -> redirect_uri
      end

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Authorize - Mooncore DevTools</title>
      <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { background: #0f172a; color: #e2e8f0; font-family: system-ui, sans-serif;
               display: flex; align-items: center; justify-content: center; min-height: 100vh; }
        .card { background: #1e293b; border: 1px solid #334155; border-radius: 12px;
                padding: 2rem; width: 100%; max-width: 420px; }
        h1 { font-size: 1.2rem; font-weight: 600; margin-bottom: 0.25rem; }
        p { font-size: 0.85rem; color: #94a3b8; margin-bottom: 1rem; }
        code { background: #0f172a; padding: 1px 5px; border-radius: 4px; font-size: 0.8rem; }
        .client-box { background: #0f172a; border: 1px solid #334155; border-radius: 6px;
                      padding: 0.6rem 0.75rem; margin-bottom: 1.25rem; font-size: 0.85rem;
                      color: #94a3b8; word-break: break-all; }
        .client-box strong { color: #e2e8f0; }
        .field { margin-bottom: 0.75rem; }
        label { display: block; font-size: 0.8rem; color: #94a3b8; margin-bottom: 0.35rem; }
        input { width: 100%; background: #0f172a; border: 1px solid #334155; border-radius: 6px;
                padding: 0.6rem 0.75rem; color: #e2e8f0; font-size: 0.9rem; outline: none; }
        input:focus { border-color: #6366f1; }
        button { margin-top: 0.75rem; width: 100%; background: #6366f1; color: white;
                 border: none; border-radius: 6px; padding: 0.65rem; font-size: 0.95rem;
                 cursor: pointer; font-weight: 500; }
        button:hover { background: #4f46e5; }
        .error { margin-top: 0.5rem; color: #f87171; font-size: 0.85rem; display: none; }
      </style>
    </head>
    <body>
      <div class="card">
        <h1>Authorize Access</h1>
        <p>An MCP client is requesting access to Mooncore DevTools.</p>
        <div class="client-box">
          Client: <strong id="client-display"></strong>
        </div>
        <div class="field">
          <label for="pw">MOONCORE_DEV_SECRET</label>
          <input type="password" id="pw" placeholder="Enter secret" autofocus>
        </div>
        <button onclick="authorize()">Authorize</button>
        <div class="error" id="err">Incorrect secret.</div>
      </div>
      <script>
        const OAUTH = {
          redirect_uri: #{Jason.encode!(redirect_uri)},
          state: #{Jason.encode!(state)},
          client_id: #{Jason.encode!(client_id)},
          code_challenge: #{Jason.encode!(code_challenge)},
          code_challenge_method: #{Jason.encode!(code_challenge_method)},
          scope: #{Jason.encode!(scope)}
        };
        document.getElementById('client-display').textContent = #{Jason.encode!(client_display)};
        async function authorize() {
          const pw = document.getElementById('pw').value;
          const res = await fetch('/oauth/authorize', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({password: pw, ...OAUTH})
          });
          const data = await res.json();
          if (res.ok && data.location) {
            window.location.href = data.location;
          } else {
            document.getElementById('err').style.display = 'block';
            document.getElementById('pw').select();
          }
        }
        document.getElementById('pw').addEventListener('keydown', e => {
          if (e.key === 'Enter') authorize();
        });
      </script>
    </body>
    </html>
    """
  end
end
