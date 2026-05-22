# Authentication

Mooncore uses JWT (JSON Web Tokens) with RS256 (RSA) signing for authentication. Tokens carry user identity, app context, and an efficiently encoded role bitmask.

## Overview

The authentication flow:

1. Your app creates a JWT when a user logs in
2. The client sends the token in the `Authorization` header (HTTP) or via `["jwt", token]` message (WebSocket)
3. Mooncore verifies the token and extracts the auth map
4. The auth map is available to every action as `req[:auth]`

## Configuration

```elixir
config :mooncore,
  jwt: [
    key: "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----",
    issuer: "myapp"
  ]
```

`key` is an RSA private key in PEM format. Generate one:

```bash
openssl genrsa -out private_key.pem 2048
```

Store the key securely — use environment variables in production:

```elixir
config :mooncore,
  jwt: [
    key: System.get_env("JWT_PRIVATE_KEY"),
    issuer: "myapp"
  ]
```

## Token Claims

Mooncore tokens contain these claims:

| Claim   | Type    | Description                                        |
| ------- | ------- | -------------------------------------------------- |
| `user`  | string  | User identifier                                    |
| `app`   | string  | App key — routes to the correct action module      |
| `tenant`| string  | Tenant key — for multi-tenant isolation            |
| `scope` | string  | Data scope — further isolation within a domain     |
| `roles` | string  | Base58-encoded bitmask of user roles               |
| `aud`   | string  | Audience — always `"api"`                          |
| `iss`   | string  | Issuer — must match configured issuer              |
| `exp`   | integer | Expiry timestamp (default: 18 hours from creation) |

## Creating Tokens

```elixir
# Define your app's roles
roles = ["admin", "user", "editor", "viewer"]

# Encode the user's roles as a Base58 bitmask
user_roles = ["user", "editor"]
encoded_roles = Mooncore.Util.Base58.from_integer(
  Mooncore.Util.Deflist.to_integer(roles, user_roles)
)

# Create the token
{:ok, token} = Mooncore.Auth.Token.new_token(%{
  "user" => "alice",
  "app" => "myapp",
  "tenant" => "acme-corp",
  "scope" => "default",
  "roles" => encoded_roles
})
```

## Verifying Tokens

Tokens are automatically verified by `Mooncore.Auth.Plug` (HTTP) or the WebSocket handler. For manual verification:

```elixir
case Mooncore.Auth.Token.solve(token_string) do
  {:ok, auth} ->
    # auth is a map with decoded claims, including decoded roles list
    IO.inspect(auth["user"])   # "alice"
    IO.inspect(auth["roles"])  # ["user", "editor"]

  {:error, reason} ->
    # Invalid or expired token
    IO.inspect(reason)
end
```

## The Auth Plug

`Mooncore.Auth.Plug` extracts the JWT from the `Authorization` header and adds the decoded auth map to the connection:

```elixir
# In your router
plug Mooncore.Auth.Plug
```

After this plug runs:
- `conn.assigns[:auth]` contains the auth map (or `nil`)
- `conn.auth` also contains the auth map (for WebSocket handler compatibility)

The plug handles:
- `Authorization: Bearer <token>` — standard Bearer token
- `Authorization: <token>` — token without Bearer prefix
- Missing or invalid tokens → `auth` is set to `nil` (not rejected — actions handle their own auth requirements)

## Role Encoding: Base58 Bitmask

Mooncore uses a compact encoding for roles. Instead of storing `["admin", "user", "editor"]` as a JSON array in the JWT, it stores a Base58-encoded integer where each bit represents a role.

### How It Works

Given a role list `["admin", "user", "editor", "viewer"]`:

```
admin  → bit 0 → 1
user   → bit 1 → 2
editor → bit 2 → 4
viewer → bit 3 → 8
```

A user with roles `["user", "editor"]` has bitmask `2 + 4 = 6`, encoded as Base58.

### Why Bitmask?

- **Compact.** A JWT with 20 roles takes the same space as one with 2 roles — a single short string.
- **Fast checking.** Role verification is a bitwise AND operation.
- **No role name leakage.** The JWT doesn't reveal what roles exist in the system — just a number.

### Using Deflist

`Mooncore.Util.Deflist` handles encoding and decoding:

```elixir
all_roles = ["admin", "user", "editor", "viewer"]
user_roles = ["user", "editor"]

# Encode: roles → integer
bitmask = Mooncore.Util.Deflist.to_integer(all_roles, user_roles)
# 6

# Decode: integer -> roles
decoded = Mooncore.Util.Deflist.from_integer(bitmask, all_roles)
# ["user", "editor"]
```

### Using Base58

`Mooncore.Util.Base58` converts integers to compact strings:

```elixir
# Encode for JWT storage
encoded = Mooncore.Util.Base58.from_integer(6)
# "7"

# Decode from JWT
decoded = Mooncore.Util.Base58.to_integer("7")
# 6
```

### Full Flow

```elixir
# At login time — encode roles into token
all_roles = MyApp.roles()
bitmask = Mooncore.Util.Deflist.to_integer(all_roles, ["user", "editor"])
role_string = Mooncore.Util.Base58.from_integer(bitmask)

{:ok, token} = Mooncore.Auth.Token.new_token(%{
  "user" => "alice",
  "app" => "myapp",
  "tenant" => "acme",
  "scope" => "default",
  "roles" => role_string
})

# At verification time — Token.solve automatically decodes roles
{:ok, auth} = Mooncore.Auth.Token.solve(token)
auth["roles"]  # ["user", "editor"]
```

## Custom Auth Strategies

Mooncore's auth system is modular. If JWT doesn't fit your needs:

1. **Skip `Mooncore.Auth.Plug`** — don't add it to your router
2. **Set auth manually** — assign `conn.assigns[:auth]` in your own plug
3. **Use any format** — the action system just needs a map at `req[:auth]` with a `"roles"` key

```elixir
defmodule MyApp.Auth.ApiKeyPlug do
  def init(opts), do: opts

  def call(conn, _opts) do
    case Plug.Conn.get_req_header(conn, "x-api-key") do
      [key] ->
        auth = MyApp.Auth.verify_api_key(key)
        conn
        |> Plug.Conn.assign(:auth, auth)
        |> Map.put(:auth, auth)

      _ ->
        conn
        |> Plug.Conn.assign(:auth, nil)
        |> Map.put(:auth, nil)
    end
  end
end
```

As long as `auth["roles"]` is a list of strings, Mooncore's role checking works with any auth strategy.
