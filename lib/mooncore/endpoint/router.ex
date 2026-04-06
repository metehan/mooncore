defmodule Mooncore.Endpoint.Router do
  @moduledoc """
  Example router for Mooncore.

  This is a reference implementation. Copy this into your project and modify it.
  You own the router — add routes, change plugs, return any HTTP status you want.

  ## Usage

  In your project, create your own router:

      defmodule MyApp.Router do
        use Plug.Router

        plug Plug.Logger
        plug CORSPlug, origin: ["*"]
        plug Mooncore.Auth.Plug
        plug Plug.Parsers,
          parsers: [:urlencoded, :multipart, {:json, json_decoder: Jason}],
          length: 100_000_000
        plug :match
        plug :dispatch

        # Action endpoint
        match "/run" do
          Mooncore.Endpoint.Http.handle(conn)
        end

        # WebSocket endpoint
        get "/ws" do
          conn
          |> WebSockAdapter.upgrade(Mooncore.Endpoint.Socket.Handler, [conn: conn], timeout: 60_000)
          |> halt()
        end

        # Dev dashboard (only active when mooncore_dev_tools: true)
        forward "/mooncore", to: Mooncore.Dev.Plug

        # Custom routes — you control everything
        get "/" do
          send_resp(conn, 200, "My App")
        end

        get "/health" do
          send_resp(conn, 200, "ok")
        end

        match _ do
          send_resp(conn, 404, "Not Found")
        end
      end

  Then configure:

      config :mooncore, router: MyApp.Router
  """
end
