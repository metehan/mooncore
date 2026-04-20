defmodule Mooncore.Auth.TokenTest do
  use ExUnit.Case, async: false

  alias Mooncore.Auth.Token

  # Generate a 1024-bit test RSA key once for the whole suite.
  # 1024-bit is used only for test speed; never use in production.
  setup_all do
    private_key = :public_key.generate_key({:rsa, 1024, 65537})
    pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
    pem = :public_key.pem_encode([pem_entry])
    {:ok, jwt_key: pem}
  end

  setup %{jwt_key: pem} do
    Application.put_env(:mooncore, :jwt, key: pem, issuer: "test_issuer")

    on_exit(fn -> Application.delete_env(:mooncore, :jwt) end)
    :ok
  end

  describe "new_token/1 and solve/1" do
    test "creates a token that verifies successfully" do
      claims = %{"user" => "alice", "app" => "myapp", "dkey" => "tenant1"}

      assert {:ok, token} = Token.new_token(claims)
      assert is_binary(token)

      assert {:ok, verified} = Token.solve(token)
      assert verified["user"] == "alice"
      assert verified["app"] == "myapp"
      assert verified["dkey"] == "tenant1"
      assert verified["aud"] == "api"
      assert verified["iss"] == "test_issuer"
      assert is_integer(verified["exp"])
    end

    test "solve rejects a garbage token" do
      assert {:error, _} = Token.solve("not.a.jwt")
    end

    test "solve rejects an empty string" do
      assert {:error, _} = Token.solve("")
    end

    test "solve rejects a token signed with a different key" do
      original_config = Application.get_env(:mooncore, :jwt)

      other_key = :public_key.generate_key({:rsa, 1024, 65537})
      other_pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, other_key)
      other_pem = :public_key.pem_encode([other_pem_entry])

      # Sign a token with a fresh key
      Application.put_env(:mooncore, :jwt, key: other_pem, issuer: "test_issuer")
      {:ok, token} = Token.new_token(%{"user" => "eve"})

      # Restore original key — token signed with other_key should now fail verification
      Application.put_env(:mooncore, :jwt, original_config)

      assert {:error, _} = Token.solve(token)
    end

    test "default expiry is set" do
      {:ok, token} = Token.new_token(%{})
      {:ok, claims} = Token.solve(token)
      now = System.system_time(:second)

      # Default is 18 hours; check it's within a reasonable window
      assert claims["exp"] > now + 60
      assert claims["exp"] < now + 64_800 + 60
    end
  end

  describe "new_token/3 with role bitmask" do
    test "encodes roles in token and decodes without app_module" do
      app_roles = ["admin", "manager", "user"]
      client_roles = ["admin", "user"]

      assert {:ok, token} =
               Token.new_token(
                 %{"user" => "bob", "app" => "myapp"},
                 app_roles,
                 client_roles
               )

      # Without app_module config, roles stay as a Base58-encoded bitmask string
      Application.delete_env(:mooncore, :app_module)
      {:ok, claims} = Token.solve(token)
      assert is_binary(claims["roles"])
    end

    test "decodes roles via configured app_module" do
      defmodule TokenTestApp do
        @behaviour Mooncore.App

        @impl true
        def list do
          %{
            "myapp" => %{
              key: "myapp",
              roles: ["admin", "manager", "user"],
              action_module: nil
            }
          }
        end

        @impl true
        def info("myapp"), do: Map.get(list(), "myapp")
        def info(_), do: nil
      end

      Application.put_env(:mooncore, :app_module, TokenTestApp)
      on_exit(fn -> Application.delete_env(:mooncore, :app_module) end)

      {:ok, token} =
        Token.new_token(
          %{"user" => "carol", "app" => "myapp"},
          ["admin", "manager", "user"],
          ["admin", "user"]
        )

      {:ok, claims} = Token.solve(token)
      assert is_list(claims["roles"])
      assert "admin" in claims["roles"]
      assert "user" in claims["roles"]
      refute "manager" in claims["roles"]
    end

    test "empty client_roles produces empty decoded roles" do
      defmodule TokenTestAppEmpty do
        @behaviour Mooncore.App

        @impl true
        def list,
          do: %{"app" => %{key: "app", roles: ["admin", "user"], action_module: nil}}

        @impl true
        def info("app"), do: Map.get(list(), "app")
        def info(_), do: nil
      end

      Application.put_env(:mooncore, :app_module, TokenTestAppEmpty)
      on_exit(fn -> Application.delete_env(:mooncore, :app_module) end)

      {:ok, token} =
        Token.new_token(%{"user" => "anon", "app" => "app"}, ["admin", "user"], [])

      {:ok, claims} = Token.solve(token)
      assert claims["roles"] == []
    end
  end

  describe "configurable JWT expiry" do
    test "respects :exp config key" do
      Application.put_env(:mooncore, :jwt,
        key: Application.get_env(:mooncore, :jwt)[:key],
        issuer: "test_issuer",
        exp: 3600
      )

      {:ok, token} = Token.new_token(%{})
      {:ok, claims} = Token.solve(token)
      now = System.system_time(:second)

      assert claims["exp"] > now
      assert claims["exp"] < now + 3700
    end
  end

  describe "Auth.Plug" do
    test "assigns nil auth when no Authorization header" do
      conn =
        Plug.Test.conn(:get, "/")
        |> Mooncore.Auth.Plug.call([])

      assert conn.assigns[:auth] == nil
    end

    test "assigns nil auth when jwt key not configured" do
      Application.delete_env(:mooncore, :jwt)

      conn =
        Plug.Test.conn(:get, "/")
        |> Plug.Conn.put_req_header("authorization", "Bearer sometoken")
        |> Mooncore.Auth.Plug.call([])

      assert conn.assigns[:auth] == nil
    end

    test "assigns auth claims when valid Bearer token provided" do
      {:ok, token} = Token.new_token(%{"user" => "dave", "app" => "test"})

      conn =
        Plug.Test.conn(:get, "/")
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
        |> Mooncore.Auth.Plug.call([])

      assert conn.assigns[:auth]["user"] == "dave"
    end

    test "assigns nil auth when token is invalid" do
      conn =
        Plug.Test.conn(:get, "/")
        |> Plug.Conn.put_req_header("authorization", "Bearer bad.token.here")
        |> Mooncore.Auth.Plug.call([])

      assert conn.assigns[:auth] == nil
    end

    test "skips extraction if auth already assigned" do
      conn =
        Plug.Test.conn(:get, "/")
        |> Plug.Conn.assign(:auth, %{"user" => "preloaded"})
        |> Mooncore.Auth.Plug.call([])

      assert conn.assigns[:auth]["user"] == "preloaded"
    end
  end
end
