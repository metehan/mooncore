defmodule Mooncore.Auth.Plug do
  @moduledoc """
  Plug that extracts JWT token from the Authorization header
  and adds the decoded auth map to the connection.

  The auth map is stored in both `conn.assigns[:auth]` and `conn.auth`
  for compatibility with the Mooncore socket handler and action system.

  ## Usage

  Add to your router's plug pipeline:

      plug Mooncore.Auth.Plug
  """

  alias Mooncore.Auth.Token

  def init(options), do: options

  def call(conn, _opts) do
    case Map.get(conn.assigns, :auth) || Map.get(conn, :auth) do
      nil -> add_auth(conn)
      _ -> conn
    end
  end

  defp add_auth(conn) do
    if Mooncore.jwt(:key) do
      conn
      |> fetch_auth_token()
      |> Token.solve()
      |> assign_auth(conn)
    else
      assign_auth({:error, :no_key}, conn)
    end
  end

  defp assign_auth({:ok, auth}, conn) do
    conn
    |> Plug.Conn.assign(:auth, auth)
    |> Map.put(:auth, auth)
  end

  defp assign_auth({:error, _}, conn) do
    conn
    |> Plug.Conn.assign(:auth, nil)
    |> Map.put(:auth, nil)
  end

  defp fetch_auth_token(conn) do
    auth =
      conn
      |> Plug.Conn.get_req_header("authorization")
      |> List.first()

    if is_binary(auth) do
      auth
      |> String.replace("Bearer ", "")
      |> String.replace("Auth: ", "")
      |> String.replace("Token: ", "")
    else
      ""
    end
  end
end
