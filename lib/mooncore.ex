defmodule Mooncore do
  @moduledoc """
  Mooncore — A lightweight, action-based api framework for Elixir.

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
        mooncore_dev_tools: true,   # also requires MOONCORE_DEV_SECRET env var
        dev_tools_allowed_ips: ["127.0.0.1", "10.0.0.0/8"],
        oauth_redirect_uris: [],    # extra OAuth redirect URI allowlist (localhost/https always allowed)
        oauth_access_token_ttl_seconds: 1_209_600, # 14 days
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

  @doc """
  Check if mooncore_dev_tools is fully enabled.

  Requires BOTH:
  - `config :mooncore, mooncore_dev_tools: true`
  - `MOONCORE_DEV_SECRET` environment variable set to a non-empty value

  This prevents accidental exposure of dev tools on servers where
  the config flag is present but no secret is configured.
  """
  def mooncore_dev_tools_enabled? do
    secret = System.get_env("MOONCORE_DEV_SECRET")
    config(:mooncore_dev_tools, false) == true and is_binary(secret) and byte_size(secret) > 0
  end

  @doc """
  Get allowed dev tool IPs.

  Returns the list from `config :mooncore, dev_tools_allowed_ips`.
  If not configured, all IPs are allowed (returns `nil` — used as "allow all" sentinel).

  Supports plain IPs (`"127.0.0.1"`, `"::1"`) and CIDR ranges
  (`"192.168.1.0/24"`, `"10.0.0.0/8"`).
  """
  def dev_tools_allowed_ips, do: config(:dev_tools_allowed_ips, nil)
end
