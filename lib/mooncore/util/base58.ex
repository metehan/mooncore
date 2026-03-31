defmodule Mooncore.Util.Base58 do
  @moduledoc """
  Base58 encoding/decoding for compact representation of integers.
  Used internally for JWT role bitmask encoding.
  """

  @alphabet "Q123456789ABCDEFGHJKLMNPRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
  @char_to_index Enum.into(Enum.with_index(to_charlist(@alphabet)), %{})
  @index_to_char @char_to_index |> Enum.map(fn {k, v} -> {v, k} end) |> Enum.into(%{})

  def from_integer(0), do: <<List.first(to_charlist(@alphabet))>>
  def from_integer(x), do: encode(x, []) |> List.to_string()

  defp encode(0, acc), do: acc
  defp encode(x, acc), do: encode(div(x, 58), [@index_to_char[rem(x, 58)] | acc])

  def to_integer(x) do
    x
    |> to_charlist()
    |> Enum.reverse()
    |> Enum.with_index()
    |> decode(0)
  end

  def from_binary(x) when byte_size(x) > 1024, do: raise("Binary too large (max 1024 bytes)")
  def from_binary(x), do: from_integer(:binary.decode_unsigned(x))
  def to_binary(x), do: :binary.encode_unsigned(to_integer(x))

  defp int_pow(_base, 0), do: 1
  defp int_pow(base, exp), do: base * int_pow(base, exp - 1)

  defp decode([], acc), do: acc

  defp decode([{x, pow} | xs], acc) do
    decode(xs, acc + @char_to_index[x] * int_pow(58, pow))
  end
end
