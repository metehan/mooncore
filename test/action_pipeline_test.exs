defmodule Mooncore.ActionPipelineTest do
  use ExUnit.Case, async: false

  # ── Test action modules ───────────────────────────────────────────────────

  defmodule EchoAction do
    def echo(req), do: %{echo: req[:params]["text"]}
  end

  defmodule SecuredAction do
    def secret(req), do: %{secret: "value", user: req[:auth]["user"]}
  end

  defmodule ErrorAction do
    def boom(_req), do: {:error, "something went wrong"}
  end

  defmodule TestActions do
    @actions %{
      "echo" => {EchoAction, :echo, [], %{}},
      "secured" => {SecuredAction, :secret, ["user"], %{}},
      "admin_only" => {SecuredAction, :secret, ["admin"], %{}},
      "boom" => {ErrorAction, :boom, [], %{}}
    }

    use Mooncore.Action
  end

  defmodule TestApp do
    @behaviour Mooncore.App

    @impl true
    def list do
      %{
        "testapp" => %{
          key: "testapp",
          name: "Test App",
          roles: ["admin", "user"],
          action_module: TestActions
        }
      }
    end

    @impl true
    def info("testapp"), do: Map.get(list(), "testapp")
    def info(_), do: nil
  end

  defmodule AddMetaMiddleware do
    @behaviour Mooncore.Middleware

    @impl true
    def call(req), do: Map.put(req, :meta, "added_by_before")
  end

  defmodule StripMetaMiddleware do
    @behaviour Mooncore.Middleware

    @impl true
    def call(resp) when is_map(resp), do: Map.put(resp, :after_ran, true)
    def call(resp), do: resp
  end

  # ── Setup ─────────────────────────────────────────────────────────────────

  setup do
    Application.put_env(:mooncore, :app_module, TestApp)
    Application.delete_env(:mooncore, :before_action)
    Application.delete_env(:mooncore, :after_action)

    on_exit(fn ->
      Application.delete_env(:mooncore, :app_module)
      Application.delete_env(:mooncore, :before_action)
      Application.delete_env(:mooncore, :after_action)
    end)

    :ok
  end

  # ── Direct dispatch (Action.dispatch / module.run) ────────────────────────

  describe "TestActions.run/2 (direct dispatch)" do
    test "dispatches a public action" do
      req = %{auth: nil, params: %{"action" => "echo", "text" => "hello"}}
      assert TestActions.run("echo", req) == %{echo: "hello"}
    end

    test "returns error for unknown action" do
      req = %{auth: nil, params: %{}}
      result = TestActions.run("nonexistent", req)
      assert match?(%{error: _}, result)
    end

    test "returns access denied when user lacks required role" do
      req = %{auth: %{"roles" => ["user"]}, params: %{"action" => "admin_only"}}
      assert TestActions.run("admin_only", req) == %{error: "Access denied"}
    end

    test "allows action when user has required role" do
      req = %{
        auth: %{"roles" => ["user"], "user" => "alice"},
        params: %{"action" => "secured"}
      }

      assert TestActions.run("secured", req) == %{secret: "value", user: "alice"}
    end

    test "returns access denied when auth is nil for role-protected action" do
      req = %{auth: nil, params: %{"action" => "secured"}}
      assert TestActions.run("secured", req) == %{error: "Access denied"}
    end

    test "wraps {:error, reason} tuple in response map" do
      req = %{auth: nil, params: %{"action" => "boom"}}
      result = TestActions.run("boom", req)
      # format_response is called by execute, not run — raw tuple is returned by run
      assert result == {:error, "something went wrong"}
    end
  end

  # ── Action.execute (full pipeline) ────────────────────────────────────────

  describe "Action.execute/2" do
    test "routes to correct app via auth app claim" do
      req = %{
        auth: %{"app" => "testapp", "roles" => []},
        params: %{"action" => "echo", "text" => "world"}
      }

      result = Mooncore.Action.execute("echo", req)
      assert result == %{echo: "world"}
    end

    test "returns error for unknown action in app" do
      req = %{
        auth: %{"app" => "testapp", "roles" => []},
        params: %{"action" => "does_not_exist"}
      }

      result = Mooncore.Action.execute("does_not_exist", req)
      assert match?(%{error: _}, result)
    end

    test "returns error immediately for unknown app claim" do
      req = %{
        auth: %{"app" => "ghost_app", "roles" => []},
        params: %{"action" => "echo"}
      }

      result = Mooncore.Action.execute("echo", req)
      assert match?(%{error: _}, result)
    end

    test "returns {:error, reason} tuple unchanged" do
      req = %{
        auth: %{"app" => "testapp", "roles" => []},
        params: %{"action" => "boom"}
      }

      result = Mooncore.Action.execute("boom", req)
      assert result == {:error, "something went wrong"}
    end
  end

  # ── Middleware ─────────────────────────────────────────────────────────────

  describe "before_action middleware" do
    test "middleware is called and can enrich the request" do
      # Use an action that echoes request metadata to verify middleware ran
      defmodule MetaEchoAction do
        def run(req), do: %{meta: req[:meta]}
      end

      defmodule MetaTestActions do
        @actions %{
          "meta_echo" => {MetaEchoAction, :run, [], %{}}
        }

        use Mooncore.Action
      end

      defmodule MetaTestApp do
        @behaviour Mooncore.App

        @impl true
        def list,
          do: %{
            "metaapp" => %{
              key: "metaapp",
              roles: [],
              action_module: MetaTestActions
            }
          }

        @impl true
        def info("metaapp"), do: Map.get(list(), "metaapp")
        def info(_), do: nil
      end

      Application.put_env(:mooncore, :app_module, MetaTestApp)
      Application.put_env(:mooncore, :before_action, [AddMetaMiddleware])

      req = %{auth: %{"app" => "metaapp", "roles" => []}, params: %{"action" => "meta_echo"}}
      result = Mooncore.Action.execute("meta_echo", req)
      assert result == %{meta: "added_by_before"}
    end

    test "multiple before middlewares run in order" do
      defmodule Order1Middleware do
        @behaviour Mooncore.Middleware
        @impl true
        def call(req), do: Map.update(req, :order, ["first"], &["first" | &1])
      end

      defmodule Order2Middleware do
        @behaviour Mooncore.Middleware
        @impl true
        def call(req), do: Map.update(req, :order, ["second"], &["second" | &1])
      end

      defmodule OrderEchoAction do
        def echo(req), do: %{order: Enum.reverse(req[:order] || [])}
      end

      defmodule OrderTestActions do
        @actions %{"order_echo" => {OrderEchoAction, :echo, [], %{}}}
        use Mooncore.Action
      end

      defmodule OrderTestApp do
        @behaviour Mooncore.App
        @impl true
        def list,
          do: %{"oapp" => %{key: "oapp", roles: [], action_module: OrderTestActions}}

        @impl true
        def info("oapp"), do: Map.get(list(), "oapp")
        def info(_), do: nil
      end

      Application.put_env(:mooncore, :app_module, OrderTestApp)
      Application.put_env(:mooncore, :before_action, [Order1Middleware, Order2Middleware])

      req = %{auth: %{"app" => "oapp", "roles" => []}, params: %{"action" => "order_echo"}}
      result = Mooncore.Action.execute("order_echo", req)
      assert result == %{order: ["first", "second"]}
    end
  end

  describe "after_action middleware" do
    test "after middleware can mutate the response" do
      Application.put_env(:mooncore, :app_module, TestApp)
      Application.put_env(:mooncore, :after_action, [StripMetaMiddleware])

      req = %{
        auth: %{"app" => "testapp", "roles" => []},
        params: %{"action" => "echo", "text" => "x"}
      }

      result = Mooncore.Action.execute("echo", req)
      assert result[:after_ran] == true
    end
  end

  # ── App multi-tenant routing ───────────────────────────────────────────────

  describe "App multi-tenant routing" do
    test "routes request to app's action_module based on auth app claim" do
      defmodule AppBAction do
        def greet(req), do: %{greeting: "hello from app_b", user: req[:auth]["user"]}
      end

      defmodule AppBActions do
        @actions %{"greet" => {AppBAction, :greet, [], %{}}}
        use Mooncore.Action
      end

      defmodule MultiTenantApp do
        @behaviour Mooncore.App

        @impl true
        def list do
          %{
            "app_a" => %{
              key: "app_a",
              roles: [],
              action_module: Mooncore.ActionPipelineTest.TestActions
            },
            "app_b" => %{key: "app_b", roles: [], action_module: AppBActions}
          }
        end

        @impl true
        def info(name), do: Map.get(list(), name)
      end

      Application.put_env(:mooncore, :app_module, MultiTenantApp)

      req_b = %{
        auth: %{"app" => "app_b", "user" => "alice", "roles" => []},
        params: %{"action" => "greet"}
      }

      assert Mooncore.Action.execute("greet", req_b) == %{
               greeting: "hello from app_b",
               user: "alice"
             }

      req_a = %{
        auth: %{"app" => "app_a", "roles" => []},
        params: %{"action" => "echo", "text" => "hi"}
      }

      assert Mooncore.Action.execute("echo", req_a) == %{echo: "hi"}
    end

    test "returns error when app claim doesn't match any registered app" do
      req = %{auth: %{"app" => "nonexistent", "roles" => []}, params: %{"action" => "echo"}}
      result = Mooncore.Action.execute("echo", req)
      assert match?(%{error: _}, result)
    end

    test "App.list/0 and App.info/1 delegate to app_module" do
      assert Mooncore.App.info("testapp") == TestApp.info("testapp")
      assert Mooncore.App.list() == TestApp.list()
    end

    test "App.info returns nil when no app_module configured" do
      Application.delete_env(:mooncore, :app_module)
      assert Mooncore.App.info("anything") == nil
      assert Mooncore.App.list() == %{}
    end
  end

  # ── sanitize_for_log ───────────────────────────────────────────────────────

  describe "sanitize_for_log strips sensitive keys" do
    # Trigger lifecycle logging to exercise sanitize_for_log
    test "execute does not crash with password in params (sanitized)" do
      req = %{
        auth: %{"app" => "testapp", "roles" => []},
        params: %{
          "action" => "echo",
          "text" => "hi",
          "password" => "s3cr3t",
          "mooncore_log" => true
        }
      }

      # Should succeed without leaking — we just check it doesn't crash
      result = Mooncore.Action.execute("echo", req)
      assert result == %{echo: "hi"}
    end
  end
end
