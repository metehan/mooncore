defmodule MooncoreTest do
  use ExUnit.Case

  describe "Mooncore.Util.Base58" do
    test "roundtrip encoding" do
      assert Mooncore.Util.Base58.to_integer(Mooncore.Util.Base58.from_integer(42)) == 42
      assert Mooncore.Util.Base58.to_integer(Mooncore.Util.Base58.from_integer(1)) == 1
      assert Mooncore.Util.Base58.to_integer(Mooncore.Util.Base58.from_integer(255)) == 255

      assert Mooncore.Util.Base58.to_integer(Mooncore.Util.Base58.from_integer(100_000)) ==
               100_000
    end
  end

  describe "Mooncore.Util.Deflist" do
    test "role bitmask roundtrip" do
      roles = ["admin", "manager", "user", "guest"]

      encoded = Mooncore.Util.Deflist.to_integer(roles, ["user", "admin"])
      decoded = Mooncore.Util.Deflist.from_integer(encoded, roles)

      assert "admin" in decoded
      assert "user" in decoded
      refute "manager" in decoded
      refute "guest" in decoded
    end

    test "empty roles" do
      roles = ["admin", "user"]
      encoded = Mooncore.Util.Deflist.to_integer(roles, [])
      decoded = Mooncore.Util.Deflist.from_integer(encoded, roles)
      assert decoded == []
    end

    test "all roles" do
      roles = ["admin", "manager", "user"]
      encoded = Mooncore.Util.Deflist.to_integer(roles, roles)
      decoded = Mooncore.Util.Deflist.from_integer(encoded, roles)
      assert Enum.sort(decoded) == Enum.sort(roles)
    end
  end

  describe "Mooncore.Action" do
    test "check_roles with nil returns false" do
      refute Mooncore.Action.check_roles(nil, ["admin"])
    end

    test "check_roles with matching role" do
      assert Mooncore.Action.check_roles(["admin", "user"], ["user"])
    end

    test "check_roles with no matching role" do
      refute Mooncore.Action.check_roles(["guest"], ["admin", "user"])
    end

    test "format_response unwraps ok tuple" do
      assert Mooncore.Action.format_response({:ok, %{id: 1}}) == %{id: 1}
    end

    test "format_response wraps error tuple" do
      assert Mooncore.Action.format_response({:error, "not found"}) == %{error: "not found"}
    end

    test "format_response passes through maps" do
      assert Mooncore.Action.format_response(%{data: 1}) == %{data: 1}
    end
  end

  describe "Mooncore config" do
    test "returns default when not configured" do
      assert Mooncore.config(:nonexistent, "fallback") == "fallback"
    end
  end
end
