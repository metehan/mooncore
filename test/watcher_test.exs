defmodule Mooncore.MCP.WatcherTest do
  use ExUnit.Case

  setup do
    # Start watcher for each test
    start_supervised!(Mooncore.MCP.Watcher)
    # Enable devmode for tests
    Application.put_env(:mooncore, :devmode, true)
    on_exit(fn -> Application.delete_env(:mooncore, :devmode) end)
    :ok
  end

  test "log and read" do
    Mooncore.MCP.Watcher.log(:test, %{message: "hello"})
    # Give the cast time to process
    :timer.sleep(10)
    logs = Mooncore.MCP.Watcher.read()
    assert length(logs) == 1
    assert hd(logs).tag == :test
    assert hd(logs).data.message == "hello"
  end

  test "read filtered by tag" do
    Mooncore.MCP.Watcher.log(:alpha, %{a: 1})
    Mooncore.MCP.Watcher.log(:beta, %{b: 2})
    Mooncore.MCP.Watcher.log(:alpha, %{a: 3})
    :timer.sleep(10)

    alpha = Mooncore.MCP.Watcher.read(:alpha)
    assert length(alpha) == 2
    beta = Mooncore.MCP.Watcher.read(:beta)
    assert length(beta) == 1
  end

  test "read_since filters by id" do
    Mooncore.MCP.Watcher.log(:x, %{n: 1})
    :timer.sleep(10)
    [first] = Mooncore.MCP.Watcher.read()

    Mooncore.MCP.Watcher.log(:x, %{n: 2})
    Mooncore.MCP.Watcher.log(:x, %{n: 3})
    :timer.sleep(10)

    since = Mooncore.MCP.Watcher.read_since(first.id)
    assert length(since) == 2
  end

  test "clear removes all logs" do
    Mooncore.MCP.Watcher.log(:test, %{a: 1})
    :timer.sleep(10)
    assert length(Mooncore.MCP.Watcher.read()) == 1

    Mooncore.MCP.Watcher.clear()
    :timer.sleep(10)
    assert Mooncore.MCP.Watcher.read() == []
  end

  test "add_watcher receives log messages" do
    Mooncore.MCP.Watcher.add_watcher(self(), :notify)
    :timer.sleep(10)

    Mooncore.MCP.Watcher.log(:notify, %{msg: "hi"})
    assert_receive {:mooncore_log, :notify, entry}, 500
    assert entry.data.msg == "hi"
  end

  test "watcher with nil filter receives all tags" do
    Mooncore.MCP.Watcher.add_watcher(self(), nil)
    :timer.sleep(10)

    Mooncore.MCP.Watcher.log(:any_tag, %{m: 1})
    assert_receive {:mooncore_log, :any_tag, _}, 500
  end

  test "watcher with tag filter ignores other tags" do
    Mooncore.MCP.Watcher.add_watcher(self(), :only_this)
    :timer.sleep(10)

    Mooncore.MCP.Watcher.log(:other, %{m: 1})
    refute_receive {:mooncore_log, _, _}, 100

    Mooncore.MCP.Watcher.log(:only_this, %{m: 2})
    assert_receive {:mooncore_log, :only_this, _}, 500
  end

  test "does not log when devmode is off" do
    Application.put_env(:mooncore, :devmode, false)
    Mooncore.MCP.Watcher.log(:test, %{should_not: true})
    :timer.sleep(10)
    assert Mooncore.MCP.Watcher.read() == []
  end
end
