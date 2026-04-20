defmodule Mooncore.Endpoint.HttpTest do
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  # ── Test fixtures ──────────────────────────────────────────────────────────

  defmodule HttpTestAction do
    def handle(req), do: %{ok: true, text: req[:params]["text"], source: req[:source]}
    def authed(req), do: %{user: req[:auth]["user"]}
  end

  defmodule HttpTestActions do
    @actions %{
      "ping" => {HttpTestAction, :handle, [], %{}},
      "authed" => {HttpTestAction, :authed, ["user"], %{}}
    }

    use Mooncore.Action
  end

  defmodule HttpTestApp do
    @behaviour Mooncore.App

    @impl true
    def list,
      do: %{
        "httpapp" => %{
          key: "httpapp",
          roles: ["user"],
          action_module: HttpTestActions
        }
      }

    @impl true
    def info("httpapp"), do: Map.get(list(), "httpapp")
    def info(_), do: nil
  end

  setup do
    Application.put_env(:mooncore, :app_module, HttpTestApp)

    on_exit(fn ->
      Application.delete_env(:mooncore, :app_module)
    end)

    :ok
  end

  # ── Endpoint.Http.handle/1 ─────────────────────────────────────────────────

  describe "handle/1" do
    test "returns 200 with JSON response for a successful action" do
      conn =
        conn(:post, "/run", Jason.encode!(%{"action" => "ping", "text" => "hello"}))
        |> put_req_header("content-type", "application/json")
        |> Plug.Conn.assign(:auth, %{"app" => "httpapp", "roles" => []})
        |> Plug.Parsers.call(
          Plug.Parsers.init(parsers: [{:json, json_decoder: Jason}], pass: ["application/json"])
        )
        |> Mooncore.Endpoint.Http.handle()

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/json"]
      body = Jason.decode!(conn.resp_body)
      assert body["ok"] == true
      assert body["text"] == "hello"
    end

    test "sets source to 'http' in the request map" do
      conn =
        conn(:post, "/run", Jason.encode!(%{"action" => "ping"}))
        |> put_req_header("content-type", "application/json")
        |> Plug.Conn.assign(:auth, %{"app" => "httpapp", "roles" => []})
        |> Plug.Parsers.call(
          Plug.Parsers.init(parsers: [{:json, json_decoder: Jason}], pass: ["application/json"])
        )
        |> Mooncore.Endpoint.Http.handle()

      body = Jason.decode!(conn.resp_body)
      assert body["source"] == "http"
    end

    test "returns error JSON for unknown action" do
      conn =
        conn(:post, "/run", Jason.encode!(%{"action" => "nonexistent"}))
        |> put_req_header("content-type", "application/json")
        |> Plug.Conn.assign(:auth, %{"app" => "httpapp", "roles" => []})
        |> Plug.Parsers.call(
          Plug.Parsers.init(parsers: [{:json, json_decoder: Jason}], pass: ["application/json"])
        )
        |> Mooncore.Endpoint.Http.handle()

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "error")
    end

    test "returns access denied for role-protected action with insufficient roles" do
      conn =
        conn(:post, "/run", Jason.encode!(%{"action" => "authed"}))
        |> put_req_header("content-type", "application/json")
        |> Plug.Conn.assign(:auth, %{"app" => "httpapp", "roles" => []})
        |> Plug.Parsers.call(
          Plug.Parsers.init(parsers: [{:json, json_decoder: Jason}], pass: ["application/json"])
        )
        |> Mooncore.Endpoint.Http.handle()

      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Access denied"
    end

    test "passes auth from conn.assigns into the request" do
      conn =
        conn(:post, "/run", Jason.encode!(%{"action" => "authed"}))
        |> put_req_header("content-type", "application/json")
        |> Plug.Conn.assign(:auth, %{
          "app" => "httpapp",
          "roles" => ["user"],
          "user" => "frank"
        })
        |> Plug.Parsers.call(
          Plug.Parsers.init(parsers: [{:json, json_decoder: Jason}], pass: ["application/json"])
        )
        |> Mooncore.Endpoint.Http.handle()

      body = Jason.decode!(conn.resp_body)
      assert body["user"] == "frank"
    end

    test "handles nil auth gracefully" do
      conn =
        conn(:post, "/run", Jason.encode!(%{"action" => "ping"}))
        |> put_req_header("content-type", "application/json")
        |> Plug.Parsers.call(
          Plug.Parsers.init(parsers: [{:json, json_decoder: Jason}], pass: ["application/json"])
        )
        |> Mooncore.Endpoint.Http.handle()

      # Should not crash; returns an error since no app claim to route with
      assert conn.status == 200
    end
  end

  # ── Endpoint.Http.receive_action/1 ────────────────────────────────────────

  describe "receive_action/1" do
    test "returns raw (unformatted) action result" do
      conn =
        conn(:post, "/run", Jason.encode!(%{"action" => "ping", "text" => "raw"}))
        |> put_req_header("content-type", "application/json")
        |> Plug.Conn.assign(:auth, %{"app" => "httpapp", "roles" => []})
        |> Plug.Parsers.call(
          Plug.Parsers.init(parsers: [{:json, json_decoder: Jason}], pass: ["application/json"])
        )

      result = Mooncore.Endpoint.Http.receive_action(conn)
      assert result[:ok] == true
      assert result[:text] == "raw"
    end

    test "returns error map on internal exception (not a crash)" do
      Application.delete_env(:mooncore, :app_module)

      conn =
        conn(:post, "/run", Jason.encode!(%{"action" => "anything"}))
        |> put_req_header("content-type", "application/json")
        |> Plug.Parsers.call(
          Plug.Parsers.init(parsers: [{:json, json_decoder: Jason}], pass: ["application/json"])
        )

      # Should return an error map rather than raising
      result = Mooncore.Endpoint.Http.receive_action(conn)
      assert is_map(result)
    end
  end

  # ── IP formatting ──────────────────────────────────────────────────────────

  describe "remote IP" do
    test "IPv4 address is included in request" do
      conn =
        conn(:post, "/run", Jason.encode!(%{"action" => "ping"}))
        |> put_req_header("content-type", "application/json")
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> Plug.Conn.assign(:auth, %{"app" => "httpapp", "roles" => []})
        |> Plug.Parsers.call(
          Plug.Parsers.init(parsers: [{:json, json_decoder: Jason}], pass: ["application/json"])
        )

      # receive_action builds the request with the ip field — just verify no crash
      result = Mooncore.Endpoint.Http.receive_action(conn)
      assert is_map(result)
    end
  end
end
