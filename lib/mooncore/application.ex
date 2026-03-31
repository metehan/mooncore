defmodule Mooncore.Application do
  @moduledoc """
  OTP Application for Mooncore.

  Starts the Bandit HTTP server and WebSocket client pools
  based on configuration.

  ## Configuration

      config :mooncore,
        port: 4000,                  # HTTP port (default: 4444)
        router: MyApp.Router,        # Your Plug.Router module
        pools: [:default, :myapp],   # WebSocket client pool names
        devmode: true,               # Enable dev dashboard & MCP
        mcp_port: 4040               # Dev/MCP port (default: 4040)
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = build_children()

    opts = [strategy: :one_for_one, name: Mooncore.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp build_children do
    router = Mooncore.config(:router)
    port = Mooncore.config(:port, 4444)
    pools = Mooncore.config(:pools, [:default])
    devmode = Mooncore.config(:devmode, false)

    server =
      if router do
        [{Bandit, plug: router, port: port}]
      else
        []
      end

    pool_children =
      pools
      |> Enum.map(fn name ->
        {Mooncore.Endpoint.Socket.Clients, name: name}
        |> Supervisor.child_spec(id: name)
      end)

    dev_children =
      if devmode do
        mcp_port = Mooncore.config(:mcp_port, 4040)

        [
          {Mooncore.MCP.Watcher, []},
          {Bandit, plug: Mooncore.Dev.Plug, port: mcp_port, scheme: :http}
          |> Supervisor.child_spec(id: :mcp_server)
        ]
      else
        []
      end

    server ++ pool_children ++ dev_children
  end
end
