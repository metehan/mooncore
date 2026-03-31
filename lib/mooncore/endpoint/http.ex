defmodule Mooncore.Endpoint.Http do
  @moduledoc """
  HTTP transport adapter.

  Converts an HTTP request (Plug.Conn) into an action call and returns the result.
  Users call this from their router.

  ## Usage in your router

      match "/run" do
        Mooncore.Endpoint.Http.handle(conn)
      end
  """

  @doc """
  Handle an HTTP request: extract action from params, build request map,
  execute action through the pipeline, return JSON response via conn.
  """
  def handle(conn) do
    response =
      receive_action(conn)
      |> Mooncore.Action.format_response()

    json =
      case Jason.encode(response) do
        {:ok, r} -> r
        _ -> "{}"
      end

    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(200, json)
  end

  @doc """
  Build request map from conn and execute the action through the pipeline.
  Returns raw action result (not formatted, not encoded).
  Use this if you want to control the HTTP response yourself.
  """
  def receive_action(conn) do
    try do
      Mooncore.Action.execute(
        conn.params["action"],
        %{
          auth: conn.assigns[:auth] || Map.get(conn, :auth, nil),
          params: conn.params
        }
      )
    rescue
      e ->
        require Logger
        Logger.error("Action error: #{inspect(e)}\n#{inspect(__STACKTRACE__)}")
        %{error: "Internal Server Error"}
    end
  end
end
