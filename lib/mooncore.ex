defmodule Mooncore do
  @moduledoc """
  Mooncore — A lightweight, action-based web framework for Elixir.

  Mooncore is a Phoenix alternative built around the action pattern:
  every feature is an action (a named operation mapped to a module function),
  and actions are transport-agnostic — the same action works via HTTP, WebSocket,
  local Elixir call, or any other protocol.

  ## Configuration

      config :mooncore,
        port: 4000,
        router: MyApp.Router,
        app_module: MyApp.App,
        jwt: [key: "...", issuer: "myapp"],
        pools: [:default],
        before_action: [],
        after_action: []
  """

  @doc "Get a mooncore config value."
  def config(key, default \\ nil) do
    Application.get_env(:mooncore, key, default)
  end

  @doc "Get a nested mooncore config value."
  def config(key, subkey, default) do
    Application.get_env(:mooncore, key, [])
    |> Access.get(subkey, default)
  end

  @doc "Get JWT config."
  def jwt(:key), do: config(:jwt, :key, nil)
  def jwt(:issuer), do: config(:jwt, :issuer, "mooncore")
  def jwt(_), do: nil
end
