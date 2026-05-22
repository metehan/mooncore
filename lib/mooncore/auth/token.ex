defmodule Mooncore.Auth.Token do
  @moduledoc """
  JWT token creation and verification.

  Uses RS256 (RSA) signing via Joken. Configuration is read from:

      config :mooncore,
        jwt: [
          key: "-----BEGIN PRIVATE KEY-----\\n...\\n-----END PRIVATE KEY-----",
          issuer: "myapp"
        ]

  ## Token Claims

  Tokens contain:
  - `"user"` — user identifier
  - `"app"` — app key (for routing to correct action module)
  - `"tenant"` — tenant key for multi-tenant isolation
  - `"scope"` — scope for data isolation
  - `"roles"` — Base58-encoded bitmask of roles
  - `"aud"` — audience ("api")
  - `"iss"` — issuer (from config)
  - `"exp"` — expiry (18 hours default)
  """

  use Joken.Config

  def signer do
    Joken.Signer.create("RS256", %{"pem" => Mooncore.jwt(:key)})
  end

  def token_config do
    exp = Mooncore.config(:jwt, :exp, 60 * 60 * 18)

    default_claims(default_exp: exp)
    |> add_claim("aud", fn -> "api" end, &(&1 == "api"))
    |> add_claim("iss", fn -> Mooncore.jwt(:issuer) end, &(&1 == Mooncore.jwt(:issuer)))
  end

  def create(claims \\ %{}) do
    generate_and_sign(claims, signer())
  end

  @doc "Create a new token with claims. Returns `{:ok, token}` or `{:error, reason}`."
  def new_token(claims \\ %{}) do
    case create(claims) do
      {:ok, token, _} -> {:ok, token}
      _ -> {:error, "token-creation-failed"}
    end
  end

  @doc """
  Create a new token with role bitmask encoding.

  `app_roles` is the ordered list of all possible roles for the app.
  `client_roles` is the list of roles this user has.
  """
  def new_token(claims, app_roles, client_roles) do
    encoded_roles =
      Mooncore.Util.Deflist.to_integer(app_roles, client_roles)
      |> Mooncore.Util.Base58.from_integer()

    case create(Map.merge(claims, %{"roles" => encoded_roles})) do
      {:ok, token, _} -> {:ok, token}
      _ -> {:error, "token-creation-failed"}
    end
  end

  @doc """
  Verify and decode a JWT token.

  Returns `{:ok, claims}` with roles decoded from bitmask back to string list,
  or `{:error, reason}`.
  """
  def solve(token) do
    case verify_and_validate(token, signer()) do
      {:ok, %{"roles" => user_roles, "app" => app_name} = claims} when is_binary(user_roles) ->
        app_info = Mooncore.App.info(app_name)

        if app_info do
          decoded_roles =
            Mooncore.Util.Base58.to_integer(user_roles)
            |> Mooncore.Util.Deflist.from_integer(app_info.roles)

          {:ok, Map.merge(claims, %{"roles" => decoded_roles})}
        else
          {:ok, claims}
        end

      {:ok, claims} ->
        {:ok, claims}

      _ ->
        {:error, "token-verification-failed"}
    end
  end
end
