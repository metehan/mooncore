defmodule Mooncore.Dev.RequestLogger do
  @moduledoc """
  Logs action calls to the dev dashboard.

  Called internally by `Mooncore.Action.execute/2` — captures all actions
  regardless of transport (HTTP, WebSocket, MCP runner).

  Logs are stored in `Mooncore.MCP.Watcher` with tag `:action`.
  Only logs when `config :mooncore, mooncore_dev_tools: true`.
  """

  @doc """
  Log an action call with its request context, result, and duration.
  Called automatically from Action.execute after every action.
  """
  def log_action(action, request, response, duration) do
    if Mooncore.mooncore_dev_tools_enabled?() do
      params = Map.drop(request[:params] || %{}, ["action"])
      auth = request[:auth]
      source = detect_source(request)

      try do
        Mooncore.MCP.Watcher.log(:action, %{
          action: action,
          params: params,
          auth: auth,
          ip: request[:ip],
          source: source,
          response: sanitize_response(response),
          duration: duration
        })
      catch
        :exit, _ -> :ok
      end
    end

    :ok
  end

  defp detect_source(request) do
    cond do
      is_binary(request[:source]) -> request[:source]
      is_atom(request[:source]) -> Atom.to_string(request[:source])
      Map.has_key?(request, :socket_pid) -> "ws"
      true -> "elixir"
    end
  end

  defp sanitize_response(resp) when is_map(resp) do
    Map.drop(resp, [:password, "password"])
  rescue
    _ -> inspect(resp)
  end

  defp sanitize_response({:ok, data}), do: %{ok: true, data: sanitize_response(data)}
  defp sanitize_response({:error, reason}), do: %{ok: false, error: sanitize_response(reason)}
  defp sanitize_response(resp) when is_tuple(resp), do: inspect(resp)
  defp sanitize_response(resp), do: resp
end
