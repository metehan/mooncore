defmodule Mooncore.ValidateTest do
  use ExUnit.Case, async: true

  alias Mooncore.Validate

  # ---------------------------------------------------------------------------
  # Presence
  # ---------------------------------------------------------------------------

  describe ":required" do
    test "passes when field is present" do
      assert {:ok, _} = Validate.run_schema(%{name: "alice"}, name: [:required])
    end

    test "fails when field is absent" do
      assert {:error, %{name: ["is required"]}} = Validate.run_schema(%{}, name: [:required])
    end

    test "fails when field is nil" do
      assert {:error, %{name: ["is required"]}} =
               Validate.run_schema(%{name: nil}, name: [:required])
    end

    test "string key — passes" do
      assert {:ok, _} = Validate.run_schema(%{"name" => "alice"}, [{"name", [:required]}])
    end

    test "string key — fails when absent" do
      assert {:error, %{"name" => ["is required"]}} =
               Validate.run_schema(%{}, [{"name", [:required]}])
    end

    test "path key — passes" do
      assert {:ok, _} =
               Validate.run_schema(%{"address" => %{"city" => "NYC"}}, [
                 {["address", "city"], [:required]}
               ])
    end

    test "path key — fails when absent" do
      assert {:error, %{["address", "city"] => ["is required"]}} =
               Validate.run_schema(%{"address" => %{}}, [{["address", "city"], [:required]}])
    end
  end

  # ---------------------------------------------------------------------------
  # Type checks
  # ---------------------------------------------------------------------------

  describe "type rules" do
    test ":string passes for binary" do
      assert {:ok, _} = Validate.run_schema(%{x: "hello"}, x: [:string])
    end

    test ":string fails for integer" do
      assert {:error, %{x: _}} = Validate.run_schema(%{x: 123}, x: [:string])
    end

    test ":integer passes for integer" do
      assert {:ok, _} = Validate.run_schema(%{x: 5}, x: [:integer])
    end

    test ":integer fails for string" do
      assert {:error, %{x: _}} = Validate.run_schema(%{x: "5"}, x: [:integer])
    end

    test ":float passes for float" do
      assert {:ok, _} = Validate.run_schema(%{x: 1.5}, x: [:float])
    end

    test ":number passes for integer and float" do
      assert {:ok, _} = Validate.run_schema(%{x: 5}, x: [:number])
      assert {:ok, _} = Validate.run_schema(%{x: 1.5}, x: [:number])
    end

    test ":boolean passes for true/false" do
      assert {:ok, _} = Validate.run_schema(%{x: true}, x: [:boolean])
      assert {:ok, _} = Validate.run_schema(%{x: false}, x: [:boolean])
    end

    test "type rules pass for nil (absence is :required's concern)" do
      assert {:ok, _} = Validate.run_schema(%{}, x: [:string])
      assert {:ok, _} = Validate.run_schema(%{}, x: [:integer])
    end
  end

  # ---------------------------------------------------------------------------
  # Numeric
  # ---------------------------------------------------------------------------

  describe "numeric rules" do
    test ":positive passes for > 0" do
      assert {:ok, _} = Validate.run_schema(%{n: 1}, n: [:positive])
    end

    test ":positive fails for 0" do
      assert {:error, %{n: _}} = Validate.run_schema(%{n: 0}, n: [:positive])
    end

    test ":non_negative passes for 0" do
      assert {:ok, _} = Validate.run_schema(%{n: 0}, n: [:non_negative])
    end

    test "{:min, n} passes" do
      assert {:ok, _} = Validate.run_schema(%{n: 10}, n: [{:min, 5}])
    end

    test "{:min, n} fails" do
      assert {:error, %{n: _}} = Validate.run_schema(%{n: 3}, n: [{:min, 5}])
    end

    test "{:max, n} passes" do
      assert {:ok, _} = Validate.run_schema(%{n: 3}, n: [{:max, 5}])
    end

    test "{:max, n} fails" do
      assert {:error, %{n: _}} = Validate.run_schema(%{n: 10}, n: [{:max, 5}])
    end

    test "{:between, min, max} passes at boundaries" do
      assert {:ok, _} = Validate.run_schema(%{n: 1}, n: [{:between, 1, 10}])
      assert {:ok, _} = Validate.run_schema(%{n: 10}, n: [{:between, 1, 10}])
    end

    test "{:between, min, max} fails outside range" do
      assert {:error, %{n: _}} = Validate.run_schema(%{n: 0}, n: [{:between, 1, 10}])
      assert {:error, %{n: _}} = Validate.run_schema(%{n: 11}, n: [{:between, 1, 10}])
    end

    test "{:multiple_of, n} passes" do
      assert {:ok, _} = Validate.run_schema(%{n: 6}, n: [{:multiple_of, 3}])
    end

    test "{:multiple_of, n} fails" do
      assert {:error, %{n: _}} = Validate.run_schema(%{n: 7}, n: [{:multiple_of, 3}])
    end
  end

  # ---------------------------------------------------------------------------
  # String length
  # ---------------------------------------------------------------------------

  describe "string length rules" do
    test "{:min_length, n} passes" do
      assert {:ok, _} = Validate.run_schema(%{s: "hello"}, s: [{:min_length, 3}])
    end

    test "{:min_length, n} fails" do
      assert {:error, %{s: _}} = Validate.run_schema(%{s: "hi"}, s: [{:min_length, 3}])
    end

    test "{:max_length, n} passes" do
      assert {:ok, _} = Validate.run_schema(%{s: "hi"}, s: [{:max_length, 5}])
    end

    test "{:max_length, n} fails" do
      assert {:error, %{s: _}} = Validate.run_schema(%{s: "toolong"}, s: [{:max_length, 5}])
    end

    test "{:length, n} passes for exact match" do
      assert {:ok, _} = Validate.run_schema(%{s: "abc"}, s: [{:length, 3}])
    end

    test "{:length, n} fails for wrong length" do
      assert {:error, %{s: _}} = Validate.run_schema(%{s: "ab"}, s: [{:length, 3}])
    end
  end

  # ---------------------------------------------------------------------------
  # String format
  # ---------------------------------------------------------------------------

  describe "string format rules" do
    test ":email passes for valid email" do
      assert {:ok, _} = Validate.run_schema(%{e: "user@example.com"}, e: [:email])
    end

    test ":email fails for invalid email" do
      assert {:error, %{e: _}} = Validate.run_schema(%{e: "not-an-email"}, e: [:email])
    end

    test ":uuid passes for valid UUID v4" do
      assert {:ok, _} =
               Validate.run_schema(%{id: "550e8400-e29b-41d4-a716-446655440000"}, id: [:uuid])
    end

    test ":uuid fails for non-UUID" do
      assert {:error, %{id: _}} = Validate.run_schema(%{id: "123"}, id: [:uuid])
    end

    test ":url passes for http/https" do
      assert {:ok, _} = Validate.run_schema(%{u: "https://example.com"}, u: [:url])
    end

    test ":url fails for invalid url" do
      assert {:error, %{u: _}} = Validate.run_schema(%{u: "not a url"}, u: [:url])
    end

    test ":iso8601 passes for valid datetime" do
      assert {:ok, _} =
               Validate.run_schema(%{t: "2024-01-15T12:00:00Z"}, t: [:iso8601])
    end

    test ":iso8601 fails for invalid datetime" do
      assert {:error, %{t: _}} = Validate.run_schema(%{t: "not a date"}, t: [:iso8601])
    end

    test ":date passes for valid date" do
      assert {:ok, _} = Validate.run_schema(%{d: "2024-01-15"}, d: [:date])
    end

    test ":date fails for invalid date" do
      assert {:error, %{d: _}} = Validate.run_schema(%{d: "01/15/2024"}, d: [:date])
    end

    test "{:regex, pattern} passes" do
      assert {:ok, _} =
               Validate.run_schema(%{s: "abc123"}, s: [{:regex, ~r/^[a-z0-9]+$/}])
    end

    test "{:regex, pattern} fails" do
      assert {:error, %{s: _}} =
               Validate.run_schema(%{s: "ABC"}, s: [{:regex, ~r/^[a-z0-9]+$/}])
    end

    test ":trimmed passes for no surrounding whitespace" do
      assert {:ok, _} = Validate.run_schema(%{s: "hello"}, s: [:trimmed])
    end

    test ":trimmed fails for leading/trailing whitespace" do
      assert {:error, %{s: _}} = Validate.run_schema(%{s: " hello"}, s: [:trimmed])
      assert {:error, %{s: _}} = Validate.run_schema(%{s: "hello "}, s: [:trimmed])
    end

    test "{:starts_with, prefix} passes" do
      assert {:ok, _} = Validate.run_schema(%{s: "hello world"}, s: [{:starts_with, "hello"}])
    end

    test "{:starts_with, prefix} fails" do
      assert {:error, %{s: _}} = Validate.run_schema(%{s: "world"}, s: [{:starts_with, "hello"}])
    end

    test "{:ends_with, suffix} passes" do
      assert {:ok, _} = Validate.run_schema(%{s: "file.txt"}, s: [{:ends_with, ".txt"}])
    end

    test "{:ends_with, suffix} fails" do
      assert {:error, %{s: _}} = Validate.run_schema(%{s: "file.md"}, s: [{:ends_with, ".txt"}])
    end
  end

  # ---------------------------------------------------------------------------
  # Membership
  # ---------------------------------------------------------------------------

  describe "membership rules" do
    test "{:in, list} passes" do
      assert {:ok, _} = Validate.run_schema(%{x: "b"}, x: [{:in, ["a", "b", "c"]}])
    end

    test "{:in, list} fails" do
      assert {:error, %{x: _}} = Validate.run_schema(%{x: "z"}, x: [{:in, ["a", "b", "c"]}])
    end

    test "{:not_in, list} passes" do
      assert {:ok, _} = Validate.run_schema(%{x: "z"}, x: [{:not_in, ["a", "b"]}])
    end

    test "{:not_in, list} fails" do
      assert {:error, %{x: _}} = Validate.run_schema(%{x: "a"}, x: [{:not_in, ["a", "b"]}])
    end
  end

  # ---------------------------------------------------------------------------
  # Collections
  # ---------------------------------------------------------------------------

  describe "collection rules" do
    test "{:list_of, :string} passes for all-string list" do
      assert {:ok, _} = Validate.run_schema(%{tags: ["a", "b"]}, tags: [{:list_of, :string}])
    end

    test "{:list_of, :string} fails when element is not a string" do
      assert {:error, %{tags: _}} =
               Validate.run_schema(%{tags: ["a", 1]}, tags: [{:list_of, :string}])
    end

    test "{:list_of, rule} fails for non-list" do
      assert {:error, %{tags: _}} =
               Validate.run_schema(%{tags: "not a list"}, tags: [{:list_of, :string}])
    end

    test "{:min_items, n} passes" do
      assert {:ok, _} = Validate.run_schema(%{xs: [1, 2, 3]}, xs: [{:min_items, 2}])
    end

    test "{:min_items, n} fails" do
      assert {:error, %{xs: _}} = Validate.run_schema(%{xs: [1]}, xs: [{:min_items, 2}])
    end

    test "{:max_items, n} passes" do
      assert {:ok, _} = Validate.run_schema(%{xs: [1]}, xs: [{:max_items, 3}])
    end

    test "{:max_items, n} fails" do
      assert {:error, %{xs: _}} = Validate.run_schema(%{xs: [1, 2, 3, 4]}, xs: [{:max_items, 3}])
    end
  end

  # ---------------------------------------------------------------------------
  # Nested
  # ---------------------------------------------------------------------------

  describe "{:nested, schema}" do
    test "passes for valid nested map" do
      schema = [address: [{:nested, [city: [:required, :string], zip: [:required, :string]]}]]

      assert {:ok, _} =
               Validate.run_schema(%{address: %{city: "NYC", zip: "10001"}}, schema)
    end

    test "fails for invalid nested field" do
      schema = [address: [{:nested, [city: [:required, :string]]}]]

      assert {:error, %{address: _}} =
               Validate.run_schema(%{address: %{}}, schema)
    end

    test "passes when nested field is nil (not required at top level)" do
      schema = [address: [{:nested, [city: [:required, :string]]}]]
      assert {:ok, _} = Validate.run_schema(%{}, schema)
    end

    test "string-keyed nested via path" do
      schema = [{["address", "city"], [:required, :string]}]

      assert {:ok, _} =
               Validate.run_schema(%{"address" => %{"city" => "NYC"}}, schema)

      assert {:error, _} =
               Validate.run_schema(%{"address" => %{}}, schema)
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-field
  # ---------------------------------------------------------------------------

  describe "cross-field rules" do
    test "{:equal_to, other} passes when equal" do
      assert {:ok, _} =
               Validate.run_schema(%{pass: "abc", confirm: "abc"},
                 confirm: [{:equal_to, :pass}]
               )
    end

    test "{:equal_to, other} fails when not equal" do
      assert {:error, %{confirm: _}} =
               Validate.run_schema(%{pass: "abc", confirm: "xyz"},
                 confirm: [{:equal_to, :pass}]
               )
    end

    test "{:greater_than, other} passes" do
      assert {:ok, _} =
               Validate.run_schema(%{max: 10, min: 5}, max: [{:greater_than, :min}])
    end

    test "{:greater_than, other} fails" do
      assert {:error, %{max: _}} =
               Validate.run_schema(%{max: 3, min: 5}, max: [{:greater_than, :min}])
    end

    test "{:only_one_of, other} passes when exactly one is present" do
      assert {:ok, _} =
               Validate.run_schema(%{email: "a@b.com"}, email: [{:only_one_of, :phone}])
    end

    test "{:only_one_of, other} fails when both present" do
      assert {:error, %{email: _}} =
               Validate.run_schema(%{email: "a@b.com", phone: "123"},
                 email: [{:only_one_of, :phone}]
               )
    end

    test "{:forbidden_with, other} passes when only one present" do
      assert {:ok, _} =
               Validate.run_schema(%{a: "x"}, a: [{:forbidden_with, :b}])
    end

    test "{:forbidden_with, other} fails when both present" do
      assert {:error, %{a: _}} =
               Validate.run_schema(%{a: "x", b: "y"}, a: [{:forbidden_with, :b}])
    end

    test "{:required_if, other, val} requires field when condition met" do
      assert {:error, %{billing: _}} =
               Validate.run_schema(%{plan: "paid"},
                 billing: [{:required_if, :plan, "paid"}]
               )
    end

    test "{:required_if, other, val} skips when condition not met" do
      assert {:ok, _} =
               Validate.run_schema(%{plan: "free"},
                 billing: [{:required_if, :plan, "paid"}]
               )
    end

    test "{:required_with, other} requires field when other is present" do
      assert {:error, %{last_name: _}} =
               Validate.run_schema(%{first_name: "Alice"},
                 last_name: [{:required_with, :first_name}]
               )
    end

    test "{:required_with, other} passes when other is absent" do
      assert {:ok, _} =
               Validate.run_schema(%{},
                 last_name: [{:required_with, :first_name}]
               )
    end
  end

  # ---------------------------------------------------------------------------
  # Custom functions
  # ---------------------------------------------------------------------------

  describe "{:fn, func}" do
    test "passes when func returns :ok" do
      assert {:ok, _} =
               Validate.run_schema(%{x: 5},
                 x: [{:fn, fn v -> if v > 0, do: :ok, else: {:error, "bad"} end}]
               )
    end

    test "fails when func returns {:error, msg}" do
      assert {:error, %{x: ["bad"]}} =
               Validate.run_schema(%{x: -1},
                 x: [{:fn, fn v -> if v > 0, do: :ok, else: {:error, "bad"} end}]
               )
    end

    test "passes when func returns true" do
      assert {:ok, _} = Validate.run_schema(%{x: 2}, x: [{:fn, fn v -> rem(v, 2) == 0 end}])
    end

    test "fails when func returns false" do
      assert {:error, %{x: _}} =
               Validate.run_schema(%{x: 3}, x: [{:fn, fn v -> rem(v, 2) == 0 end}])
    end

    test "{:fn, func, msg} uses custom error message" do
      assert {:error, %{x: ["must be even"]}} =
               Validate.run_schema(%{x: 3},
                 x: [{:fn, fn v -> rem(v, 2) == 0 end, "must be even"}]
               )
    end
  end

  # ---------------------------------------------------------------------------
  # Pipeline API (rule/3 + run/1)
  # ---------------------------------------------------------------------------

  describe "pipeline API" do
    test "run/1 validates and strips metadata" do
      result =
        %{name: "alice", age: 25}
        |> Validate.rule(:name, [:required, :string])
        |> Validate.rule(:age, [:required, :integer, :positive])
        |> Validate.run()

      assert {:ok, data} = result
      refute Map.has_key?(data, :__validations__)
    end

    test "run/2 calls success fn on success" do
      result =
        %{name: "alice"}
        |> Validate.rule(:name, [:required, :string])
        |> Validate.run(fn data -> {:wrapped, data} end)

      assert {:wrapped, %{name: "alice"}} = result
    end

    test "run/2 returns error tuple on failure, does not call success fn" do
      result =
        %{}
        |> Validate.rule(:name, [:required])
        |> Validate.run(fn _data -> flunk("should not be called") end)

      assert {:error, %{name: _}} = result
    end

    test "string key via rule/3" do
      result =
        %{"title" => "hello"}
        |> Validate.rule("title", [:required, :string, {:min_length, 2}])
        |> Validate.run()

      assert {:ok, _} = result
    end

    test "path key via rule/3" do
      result =
        %{"address" => %{"city" => "NYC"}}
        |> Validate.rule(["address", "city"], [:required, :string])
        |> Validate.run()

      assert {:ok, _} = result
    end
  end

  # ---------------------------------------------------------------------------
  # Error collection across fields
  # ---------------------------------------------------------------------------

  describe "error collection" do
    test "collects errors from multiple fields" do
      result =
        Validate.run_schema(
          %{},
          name: [:required],
          email: [:required],
          age: [:required]
        )

      assert {:error, errors} = result
      assert Map.has_key?(errors, :name)
      assert Map.has_key?(errors, :email)
      assert Map.has_key?(errors, :age)
    end

    test "short-circuits within a field on first failure" do
      result = Validate.run_schema(%{x: "hi"}, x: [{:min_length, 10}, {:max_length, 5}])
      assert {:error, %{x: [msg]}} = result
      assert String.contains?(msg, "at least 10")
    end

    test "build_schema/1 works with tuple list" do
      schema =
        Validate.build_schema([
          {:name, [:required, :string]},
          {"email", [:required, :email]}
        ])

      assert {:ok, _} =
               Validate.run_schema(
                 %{name: "alice"} |> Map.put("email", "alice@example.com"),
                 schema
               )
    end
  end
end
