defmodule Mooncore.Dev.PlugTest do
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  if System.get_env("MOONCORE_DEV_TOOLS") != "true" do
    IO.puts("\n  [skip] Mooncore.Dev.PlugTest — run with: MOONCORE_DEV_TOOLS=true mix test")
  end

  @moduletag skip:
               if(System.get_env("MOONCORE_DEV_TOOLS") == "true",
                 do: false,
                 else: "MOONCORE_DEV_TOOLS=true not set"
               )

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp call(method, path, body \\ %{}) do
    conn(method, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Mooncore.Dev.Plug.call([])
  end

  defp call_authed(method, path, body \\ %{}) do
    secret = System.get_env("MOONCORE_DEV_SECRET") || ""

    conn(method, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-dev-secret", secret)
    |> Mooncore.Dev.Plug.call([])
  end

  defp json_body(conn) do
    Jason.decode!(conn.resp_body)
  end

  defp issue_oauth_token do
    verifier = "mooncore-test-code-verifier"

    challenge =
      :crypto.hash(:sha256, verifier)
      |> Base.url_encode64(padding: false)

    authorize_conn =
      call(:post, "/oauth/authorize", %{
        "password" => System.fetch_env!("MOONCORE_DEV_SECRET"),
        "redirect_uri" => "http://localhost/callback",
        "state" => "test-state",
        "code_challenge" => challenge
      })

    location = json_body(authorize_conn)["location"]

    code =
      location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("code")

    token_conn =
      call(:post, "/oauth/token", %{
        "grant_type" => "authorization_code",
        "code" => code,
        "code_verifier" => verifier
      })

    {token_conn, json_body(token_conn)}
  end

  # ── Setup ──────────────────────────────────────────────────────────────────

  setup do
    Application.put_env(:mooncore, :mooncore_dev_tools, true)
    start_supervised!(Mooncore.MCP.Watcher)

    on_exit(fn ->
      Application.delete_env(:mooncore, :mooncore_dev_tools)
      Application.delete_env(:mooncore, :oauth_access_token_ttl_seconds)
    end)

    :ok
  end

  # ── Devtools gate ──────────────────────────────────────────────────────────

  describe "devtools gate" do
    test "returns 404 when mooncore_dev_tools config is false" do
      Application.put_env(:mooncore, :mooncore_dev_tools, false)

      conn = call(:get, "/")
      assert conn.status == 404
    end
  end

  # ── Dev auth ──────────────────────────────────────────────────────────────

  describe "dev auth" do
    test "allows all routes through when MOONCORE_DEV_SECRET is not set" do
      System.delete_env("MOONCORE_DEV_SECRET")
      conn = call(:get, "/api/actions")
      assert conn.status == 200
    end

    test "returns login page for browser requests when secret is set but not provided" do
      System.put_env("MOONCORE_DEV_SECRET", "test_secret_123")
      on_exit(fn -> System.delete_env("MOONCORE_DEV_SECRET") end)

      conn = call(:get, "/")
      assert conn.status == 200
      assert conn.resp_body =~ "Mooncore DevTools"
      assert conn.resp_body =~ "password"
    end

    test "returns 401 JSON for API requests without secret header" do
      System.put_env("MOONCORE_DEV_SECRET", "test_secret_123")
      on_exit(fn -> System.delete_env("MOONCORE_DEV_SECRET") end)

      conn = call(:get, "/api/actions")
      assert conn.status == 401
      assert json_body(conn)["error"] == "unauthorized"
    end

    test "POST /dev/login sets cookie on correct password" do
      System.put_env("MOONCORE_DEV_SECRET", "my_dev_secret")
      on_exit(fn -> System.delete_env("MOONCORE_DEV_SECRET") end)

      conn = call(:post, "/dev/login", %{"password" => "my_dev_secret"})
      assert conn.status == 200
      assert json_body(conn)["ok"] == true

      assert Enum.any?(
               get_resp_header(conn, "set-cookie"),
               &String.starts_with?(&1, "mooncore_dev=")
             )
    end

    test "POST /dev/login returns 401 on wrong password" do
      System.put_env("MOONCORE_DEV_SECRET", "my_dev_secret")
      on_exit(fn -> System.delete_env("MOONCORE_DEV_SECRET") end)

      conn = call(:post, "/dev/login", %{"password" => "wrong"})
      assert conn.status == 401
      assert json_body(conn)["error"] == "invalid password"
    end

    test "x-dev-secret header grants access" do
      System.put_env("MOONCORE_DEV_SECRET", "header_secret")
      on_exit(fn -> System.delete_env("MOONCORE_DEV_SECRET") end)

      conn = call_authed(:get, "/api/actions")
      assert conn.status == 200
    end
  end

  # ── OAuth authentication ──────────────────────────────────────────────────

  describe "OAuth authentication" do
    setup do
      original_secret = System.get_env("MOONCORE_DEV_SECRET")
      System.put_env("MOONCORE_DEV_SECRET", "oauth_test_secret")

      on_exit(fn ->
        if original_secret do
          System.put_env("MOONCORE_DEV_SECRET", original_secret)
        else
          System.delete_env("MOONCORE_DEV_SECRET")
        end
      end)

      :ok
    end

    test "issues access tokens that remain valid for 14 days by default" do
      {conn, body} = issue_oauth_token()

      assert conn.status == 200
      assert body["token_type"] == "Bearer"
      assert body["expires_in"] in 1_209_599..1_209_600

      authed_conn =
        conn(:get, "/api/actions")
        |> put_req_header("authorization", "Bearer #{body["access_token"]}")
        |> Mooncore.Dev.Plug.call([])

      assert authed_conn.status == 200
    end

    test "uses the configured access token lifetime" do
      Application.put_env(:mooncore, :oauth_access_token_ttl_seconds, 600)

      {_conn, body} = issue_oauth_token()

      assert body["expires_in"] in 599..600
    end

    test "falls back to 14 days for an invalid configured lifetime" do
      Application.put_env(:mooncore, :oauth_access_token_ttl_seconds, -1)

      {_conn, body} = issue_oauth_token()

      assert body["expires_in"] in 1_209_599..1_209_600
    end
  end

  # ── GET / ──────────────────────────────────────────────────────────────────

  describe "GET /" do
    test "returns HTML dashboard" do
      conn = call_authed(:get, "/")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    end
  end

  # ── POST /mcp (JSON-RPC 2.0) ───────────────────────────────────────────────

  describe "POST /mcp" do
    test "handles initialize request" do
      body = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{"protocolVersion" => "2024-11-05", "capabilities" => %{}}
      }

      conn = call_authed(:post, "/mcp", body)
      assert conn.status == 200
      resp = json_body(conn)
      assert resp["jsonrpc"] == "2.0"
      assert resp["id"] == 1
      assert get_in(resp, ["result", "protocolVersion"]) != nil
    end

    test "handles batch requests" do
      requests = [
        %{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"},
        %{"jsonrpc" => "2.0", "id" => 2, "method" => "ping"}
      ]

      conn =
        conn(:post, "/mcp", Jason.encode!(requests))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-dev-secret", System.get_env("MOONCORE_DEV_SECRET") || "")
        |> Mooncore.Dev.Plug.call([])

      assert conn.status == 200
      resp = json_body(conn)
      assert is_list(resp)
      assert length(resp) == 2
    end

    test "returns 202 for notification (no id)" do
      body = %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}

      conn = call_authed(:post, "/mcp", body)
      assert conn.status == 202
    end

    test "returns 400 for parse error" do
      # Plug.Parsers raises on invalid JSON before the route handler runs
      assert_raise Plug.Parsers.ParseError, fn ->
        conn(:post, "/mcp", "not json at all")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-dev-secret", System.get_env("MOONCORE_DEV_SECRET") || "")
        |> Mooncore.Dev.Plug.call([])
      end
    end
  end

  # ── POST /api/eval ─────────────────────────────────────────────────────────

  describe "POST /api/eval" do
    test "evaluates Elixir code and returns result" do
      conn = call_authed(:post, "/api/eval", %{"code" => "1 + 1"})
      assert conn.status == 200
      resp = json_body(conn)
      # eval returns inspect(result), so integers come back as strings
      assert resp["result"] == "2"
    end

    test "returns error for invalid code" do
      conn = call_authed(:post, "/api/eval", %{"code" => "this is not valid elixir !!!"})
      assert conn.status == 200
      resp = json_body(conn)
      assert Map.has_key?(resp, "error")
    end

    test "returns error when devtools is not enabled" do
      # Temporarily disable devtools at config level
      Application.put_env(:mooncore, :mooncore_dev_tools, false)
      conn = call(:post, "/api/eval", %{"code" => "1 + 1"})
      # Either 404 (gate) or error in body
      assert conn.status in [400, 404]
      Application.put_env(:mooncore, :mooncore_dev_tools, true)
    end
  end

  # ── GET /api/actions ───────────────────────────────────────────────────────

  describe "GET /api/actions" do
    test "returns list of actions" do
      conn = call_authed(:get, "/api/actions")
      assert conn.status == 200
      resp = json_body(conn)
      assert Map.has_key?(resp, "actions")
    end
  end

  # ── GET /api/config ────────────────────────────────────────────────────────

  describe "GET /api/config" do
    test "returns server config info" do
      conn = call_authed(:get, "/api/config")
      assert conn.status == 200
      resp = json_body(conn)
      assert Map.has_key?(resp, "config")
    end
  end

  # ── GET /api/apps ──────────────────────────────────────────────────────────

  describe "GET /api/apps" do
    test "returns list of apps" do
      conn = call_authed(:get, "/api/apps")
      assert conn.status == 200
      resp = json_body(conn)
      assert Map.has_key?(resp, "apps")
    end
  end

  # ── GET /api/logs ──────────────────────────────────────────────────────────

  describe "GET /api/logs" do
    test "returns log entries" do
      Mooncore.MCP.Watcher.log(:test, %{msg: "test log entry"})
      :timer.sleep(20)

      conn = call_authed(:get, "/api/logs")
      assert conn.status == 200
      resp = json_body(conn)
      assert Map.has_key?(resp, "logs")
      assert is_list(resp["logs"])
    end
  end

  # ── GET /api/dashboard ─────────────────────────────────────────────────────

  describe "GET /api/dashboard" do
    test "returns VM stats" do
      conn = call_authed(:get, "/api/dashboard")
      assert conn.status == 200
      resp = json_body(conn)
      assert Map.has_key?(resp, "memory")
      assert Map.has_key?(resp, "vm")
      assert Map.has_key?(resp, "ets_tables")
      assert Map.has_key?(resp, "applications")
    end
  end

  # ── GET /api/files and GET /api/file ──────────────────────────────────────

  describe "file browser API" do
    test "GET /api/files lists project root" do
      conn =
        conn(:get, "/api/files?path=.")
        |> put_req_header("x-dev-secret", System.get_env("MOONCORE_DEV_SECRET") || "")
        |> Mooncore.Dev.Plug.call([])

      assert conn.status == 200
      resp = json_body(conn)
      assert Map.has_key?(resp, "items")
      assert is_list(resp["items"])
    end

    test "GET /api/file reads a file" do
      conn =
        conn(:get, "/api/file?path=mix.exs")
        |> put_req_header("x-dev-secret", System.get_env("MOONCORE_DEV_SECRET") || "")
        |> Mooncore.Dev.Plug.call([])

      assert conn.status == 200
      resp = json_body(conn)
      assert resp["content"] =~ "Mooncore"
    end

    test "GET /api/file returns 403 for path traversal attempt" do
      conn =
        conn(:get, "/api/file?path=../../etc/passwd")
        |> put_req_header("x-dev-secret", System.get_env("MOONCORE_DEV_SECRET") || "")
        |> Mooncore.Dev.Plug.call([])

      assert conn.status == 403
    end

    test "GET /api/files returns 403 for path traversal attempt" do
      conn =
        conn(:get, "/api/files?path=../../etc")
        |> put_req_header("x-dev-secret", System.get_env("MOONCORE_DEV_SECRET") || "")
        |> Mooncore.Dev.Plug.call([])

      assert conn.status == 403
    end
  end

  # ── Guides API ─────────────────────────────────────────────────────────────

  describe "guides API" do
    test "GET /api/guides lists guide files" do
      conn = call_authed(:get, "/api/guides")
      assert conn.status == 200
      resp = json_body(conn)
      assert Map.has_key?(resp, "guides")
    end

    test "GET /api/guide returns 403 for non-.md file" do
      conn =
        conn(:get, "/api/guide?name=../mix.exs")
        |> put_req_header("x-dev-secret", System.get_env("MOONCORE_DEV_SECRET") || "")
        |> Mooncore.Dev.Plug.call([])

      assert conn.status in [403, 404]
    end
  end

  # ── 404 catch-all ──────────────────────────────────────────────────────────

  describe "unknown routes" do
    test "returns 404" do
      conn = call_authed(:get, "/does/not/exist")
      assert conn.status == 404
    end
  end
end
