defmodule Mooncore.ValidatedActionTest do
  use ExUnit.Case, async: false

  # ---------------------------------------------------------------------------
  # Test handlers
  # ---------------------------------------------------------------------------

  defmodule TaskHandler do
    def create(req), do: %{ok: true, title: req[:params]["title"]}
    def list(_req), do: %{tasks: []}
  end

  defmodule ReportHandler do
    def generate(req), do: %{format: req[:format]}
  end

  # ---------------------------------------------------------------------------
  # Action modules
  # ---------------------------------------------------------------------------

  defmodule ValidatedActions do
    @actions %{
      # New map format with string-keyed validate schema
      "task.create" => %{
        handler: {TaskHandler, :create},
        roles: ["user"],
        validate: [
          {"title", [:required, :string, {:min_length, 2}, {:max_length, 100}]},
          {"priority", [:integer, {:in, [1, 2, 3]}]}
        ]
      },
      # Map format, public, no validation
      "task.list" => %{
        handler: {TaskHandler, :list}
      },
      # Map format with overrides and validation
      "report.pdf" => %{
        handler: {ReportHandler, :generate},
        roles: ["admin"],
        overrides: %{format: "pdf"},
        validate: [
          {"title", [:required, :string]}
        ]
      },
      # Legacy 2-tuple: public, no overrides
      "legacy.public" => {TaskHandler, :list},
      # Legacy 3-tuple: with roles
      "legacy.secured" => {TaskHandler, :list, ["user"]},
      # Legacy 4-tuple: roles + overrides
      "legacy.echo" => {TaskHandler, :list, [], %{}},
      # Legacy 5-tuple: roles + overrides + validate
      "legacy.validated" =>
        {TaskHandler, :create, ["user"], %{},
         [
           {"title", [:required, :string, {:min_length, 2}]}
         ]}
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
          action_module: ValidatedActions
        }
      }
    end

    @impl true
    def info("testapp"), do: Map.get(list(), "testapp")
    def info(_), do: nil
  end

  # ---------------------------------------------------------------------------
  # Setup
  # ---------------------------------------------------------------------------

  setup do
    Application.put_env(:mooncore, :app_module, TestApp)
    Application.delete_env(:mooncore, :before_action)
    Application.delete_env(:mooncore, :after_action)

    on_exit(fn ->
      Application.delete_env(:mooncore, :app_module)
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Validation pass — action runs
  # ---------------------------------------------------------------------------

  describe "validation passes" do
    test "action runs when all required fields present and valid" do
      req = %{
        auth: %{"roles" => ["user"]},
        params: %{"action" => "task.create", "title" => "Buy milk", "priority" => 2}
      }

      assert ValidatedActions.run("task.create", req) == %{ok: true, title: "Buy milk"}
    end

    test "optional field absent — action still runs" do
      req = %{
        auth: %{"roles" => ["user"]},
        params: %{"action" => "task.create", "title" => "Buy milk"}
      }

      assert ValidatedActions.run("task.create", req) == %{ok: true, title: "Buy milk"}
    end

    test "action with no validate key always runs" do
      req = %{auth: nil, params: %{"action" => "task.list"}}
      assert ValidatedActions.run("task.list", req) == %{tasks: []}
    end

    test "overrides are applied after validation" do
      req = %{
        auth: %{"roles" => ["admin"]},
        params: %{"action" => "report.pdf", "title" => "Q1 Report", "format" => "csv"}
      }

      # "format" from caller is ignored; override wins
      result = ValidatedActions.run("report.pdf", req)
      assert result == %{format: "pdf"}
    end

    test "legacy 2-tuple: public, no roles, no overrides" do
      req = %{auth: nil, params: %{"action" => "legacy.public"}}
      assert ValidatedActions.run("legacy.public", req) == %{tasks: []}
    end

    test "legacy 3-tuple: role check enforced" do
      req = %{auth: %{"roles" => ["user"]}, params: %{"action" => "legacy.secured"}}
      assert ValidatedActions.run("legacy.secured", req) == %{tasks: []}
    end

    test "legacy 3-tuple: access denied without role" do
      req = %{auth: %{"roles" => []}, params: %{"action" => "legacy.secured"}}
      assert ValidatedActions.run("legacy.secured", req) == %{error: "Access denied"}
    end

    test "legacy 4-tuple: public with empty roles and overrides" do
      req = %{auth: nil, params: %{"action" => "legacy.echo"}}
      assert ValidatedActions.run("legacy.echo", req) == %{tasks: []}
    end

    test "legacy 5-tuple: validation passes, action runs" do
      req = %{
        auth: %{"roles" => ["user"]},
        params: %{"action" => "legacy.validated", "title" => "Valid title"}
      }

      assert ValidatedActions.run("legacy.validated", req) == %{ok: true, title: "Valid title"}
    end

    test "legacy 5-tuple: validation fails, returns error" do
      req = %{
        auth: %{"roles" => ["user"]},
        params: %{"action" => "legacy.validated"}
      }

      result = ValidatedActions.run("legacy.validated", req)
      assert %{error: "validation_failed", errors: %{"title" => _}} = result
    end
  end

  # ---------------------------------------------------------------------------
  # Validation fail — error returned before handler
  # ---------------------------------------------------------------------------

  describe "validation fails" do
    test "returns validation_failed when required field is absent" do
      req = %{
        auth: %{"roles" => ["user"]},
        params: %{"action" => "task.create"}
      }

      result = ValidatedActions.run("task.create", req)
      assert %{error: "validation_failed", errors: errors} = result
      assert Map.has_key?(errors, "title")
      assert "is required" in errors["title"]
    end

    test "returns validation_failed when string field fails rule" do
      req = %{
        auth: %{"roles" => ["user"]},
        params: %{"action" => "task.create", "title" => "x"}
      }

      result = ValidatedActions.run("task.create", req)
      assert %{error: "validation_failed", errors: %{"title" => _}} = result
    end

    test "returns validation_failed when integer field fails {:in, list}" do
      req = %{
        auth: %{"roles" => ["user"]},
        params: %{"action" => "task.create", "title" => "Valid title", "priority" => 9}
      }

      result = ValidatedActions.run("task.create", req)
      assert %{error: "validation_failed", errors: %{"priority" => _}} = result
    end

    test "collects errors across multiple failing fields" do
      req = %{
        auth: %{"roles" => ["user"]},
        params: %{"action" => "task.create", "priority" => 9}
      }

      result = ValidatedActions.run("task.create", req)
      assert %{error: "validation_failed", errors: errors} = result
      assert Map.has_key?(errors, "title")
      assert Map.has_key?(errors, "priority")
    end
  end

  # ---------------------------------------------------------------------------
  # Role check runs before validation
  # ---------------------------------------------------------------------------

  describe "role check before validation" do
    test "access denied returned without running validation when roles missing" do
      req = %{
        auth: %{"roles" => ["user"]},
        # user role cannot access admin-only report.pdf
        params: %{"action" => "report.pdf"}
        # note: title is missing — but we never reach validation
      }

      result = ValidatedActions.run("report.pdf", req)
      assert result == %{error: "Access denied"}
    end

    test "access denied when auth is nil for role-protected validated action" do
      req = %{
        auth: nil,
        params: %{"action" => "task.create", "title" => "anything"}
      }

      assert ValidatedActions.run("task.create", req) == %{error: "Access denied"}
    end
  end

  # ---------------------------------------------------------------------------
  # Via execute/2 (full pipeline)
  # ---------------------------------------------------------------------------

  describe "Action.execute/2 with validation" do
    test "valid request goes through pipeline and returns result" do
      req = %{
        auth: %{"app" => "testapp", "roles" => ["user"]},
        params: %{"action" => "task.create", "title" => "Do something"}
      }

      result = Mooncore.Action.execute("task.create", req)
      assert result == %{ok: true, title: "Do something"}
    end

    test "invalid request returns validation error through pipeline" do
      req = %{
        auth: %{"app" => "testapp", "roles" => ["user"]},
        params: %{"action" => "task.create"}
      }

      result = Mooncore.Action.execute("task.create", req)
      assert %{error: "validation_failed", errors: %{"title" => _}} = result
    end
  end
end
