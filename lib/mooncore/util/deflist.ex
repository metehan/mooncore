defmodule Mooncore.Util.Deflist do
  @moduledoc """
  Converts between role lists and bitmask integers.
  Used for compact JWT role encoding.

  ## How it works

  Given an ordered role list `["admin", "manager", "user"]`:
  - `["user"]` → binary `"100"` → integer `4`
  - `["admin", "user"]` → binary `"101"` → integer `5`
  - `["admin", "manager", "user"]` → binary `"111"` → integer `7`

  The integer is then Base58-encoded for the JWT token.
  """

  @doc """
  Encode a list of role strings into an integer bitmask.

  `roles` is the full ordered list of possible roles.
  `list` is the user's active roles.
  """
  def to_integer(roles, list) do
    Enum.map(roles, fn r ->
      if Enum.member?(list, r), do: "1", else: "0"
    end)
    |> Enum.join()
    |> String.reverse()
    |> String.to_integer(2)
  end

  @doc """
  Decode an integer bitmask back into a list of role strings.

  `number` is the bitmask integer.
  `list` is the full ordered list of possible roles.
  """
  def from_integer(number, list) do
    number
    |> Integer.to_string(2)
    |> String.reverse()
    |> String.graphemes()
    |> Enum.with_index(fn el, i -> if el == "1", do: Enum.at(list, i) end)
    |> Enum.reject(&is_nil/1)
  end
end
