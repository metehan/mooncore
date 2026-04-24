defmodule Mooncore.Validate do
  @moduledoc """
  A composable, pipeline-friendly data validation module.

  ## Field Keys

  Schema field keys determine which key is looked up in the data map — the key
  type is the contract, no automatic conversion happens:

  - **Atom key** `:title` — matches `%{title: "..."}` (atom-keyed maps)
  - **String key** `"title"` — matches `%{"title" => "..."}` (HTTP/WebSocket params)
  - **Path** `["address", "city"]` — matches nested `%{"address" => %{"city" => "..."}}`

  ## Usage

      # Atom-keyed data (internal Elixir calls)
      result =
        %{name: "Alice", age: 20, email: "alice@example.com", tags: ["elixir", "phoenix"]}
        |> Validate.rule(:name,  [:required, :string, {:min_length, 2}])
        |> Validate.rule(:age,   [:required, :integer, :positive, {:between, 18, 120}])
        |> Validate.rule(:email, [:required, :email])
        |> Validate.rule(:tags,  [{:list_of, :string}, {:max_items, 10}])
        |> Validate.run()

      # String-keyed data (HTTP/WebSocket params)
      result =
        %{"name" => "Alice", "age" => 20}
        |> Validate.rule("name", [:required, :string, {:min_length, 2}])
        |> Validate.rule("age",  [:required, :integer, {:between, 18, 120}])
        |> Validate.run()

      case result do
        {:ok, data}       -> data    # clean map, metadata key stripped
        {:error, errors}  -> errors  # %{field => [message, ...]} — serializes directly to JSON
      end

  Error example:

      {:error, %{name: ["is required"], age: ["must be positive", "must be between 18 and 120"]}}

  ## Schemas

  Pre-register a reusable field->rules map with `build_schema/1`:

      @user_schema Validate.build_schema([
        {:name,  [:required, :string]},
        {"email", [:required, :email]},
        {["address", "city"], [:required, :string]},
        {:age,   [:required, :integer, {:between, 18, 120}]}
      ])

      Validate.run_schema(data, @user_schema)

  > **Note:** `build_schema/1` accepts a plain list of `{field, rules}` tuples,
  > not a keyword list, so that string and path keys can be used alongside atom keys.
  > Atom-key-only schemas can still use the keyword shorthand:
  >
  >     Validate.build_schema(name: [:required, :string], age: [:required, :integer])

  ## Available Rules

  **Presence**
    - `:required`                        — field must be present and non-nil

  **Type checks** (nil passes — absence is `:required`'s concern)
    - `:string`                          — must be a binary
    - `:integer`                         — must be an integer
    - `:float`                           — must be a float
    - `:number`                          — must be an integer or float
    - `:boolean`                         — must be a boolean

  **Numeric**
    - `{:min, n}`                        — value >= n
    - `{:max, n}`                        — value <= n
    - `{:between, min, max}`             — min <= value <= max (inclusive)
    - `:positive`                        — value > 0
    - `:non_negative`                    — value >= 0
    - `{:multiple_of, n}`               — value is divisible by n

  **String length**
    - `{:min_length, n}`                 — string length >= n
    - `{:max_length, n}`                 — string length <= n
    - `{:length, n}`                     — string length == n

  **String format**
    - `:email`                           — basic structural email check
    - `:uuid`                            — UUID v4 format
    - `:url`                             — http/https URL
    - `:iso8601`                         — datetime string (uses DateTime.from_iso8601/1)
    - `:date`                            — date string YYYY-MM-DD
    - `{:regex, pattern}`                — matches a compiled Regex
    - `:trimmed`                         — no leading or trailing whitespace
    - `{:starts_with, prefix}`           — string starts with prefix
    - `{:ends_with, suffix}`             — string ends with suffix

  **Membership**
    - `{:in, list}`                      — value is a member of list
    - `{:not_in, list}`                  — value is not a member of list

  **Collections**
    - `{:list_of, rule}`                 — every list element passes rule; also guards list type
    - `{:min_items, n}`                  — list has at least n elements
    - `{:max_items, n}`                  — list has at most n elements
    - `{:nested, schema}`                — validates a nested map; schema is a list of `{field, rules}` tuples

  **Cross-field**
    - `{:equal_to, other_field}`         — value == value of other_field
    - `{:greater_than, other_field}`     — numeric value > numeric value of other_field
    - `{:only_one_of, other_field}`      — exactly one of the two fields is present/non-nil
    - `{:forbidden_with, other_field}`   — field must be absent when other_field is present
    - `{:required_if, other_field, val}` — field is required when other_field == val
    - `{:required_with, other_field}`    — field is required when other_field is present

  **Custom**
    - `{:fn, func}`                      — func.(value) returns :ok | {:ok, v} | {:error, msg} | boolean
    - `{:fn, func, error_message}`       — func.(value) returns truthy; uses error_message on failure
  """

  @metadata_key :__validations__

  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/
  @uuid_regex ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
  @url_regex ~r/^https?:\/\/[^\s$.?#].[^\s]*$/i
  @date_regex ~r/^\d{4}-\d{2}-\d{2}$/

  @type field :: atom() | String.t() | [String.t()]
  @type rule ::
          :required
          | :string
          | :integer
          | :float
          | :number
          | :boolean
          | {:min, number()}
          | {:max, number()}
          | {:between, number(), number()}
          | :positive
          | :non_negative
          | {:multiple_of, number()}
          | {:min_length, non_neg_integer()}
          | {:max_length, non_neg_integer()}
          | {:length, non_neg_integer()}
          | :email
          | :uuid
          | :url
          | :iso8601
          | :date
          | {:regex, Regex.t()}
          | :trimmed
          | {:starts_with, String.t()}
          | {:ends_with, String.t()}
          | {:in, list()}
          | {:not_in, list()}
          | {:list_of, rule()}
          | {:min_items, non_neg_integer()}
          | {:max_items, non_neg_integer()}
          | {:nested, [{field(), [rule()]}]}
          | {:equal_to, field()}
          | {:greater_than, field()}
          | {:only_one_of, field()}
          | {:forbidden_with, field()}
          | {:required_if, field(), any()}
          | {:required_with, field()}
          | {:fn, (any() -> boolean() | {:ok, any()} | {:error, String.t()})}
          | {:fn, (any() -> boolean()), String.t()}

  @type validation_data :: map()
  @type errors :: %{field() => [String.t()]}
  @type result :: {:ok, validation_data()} | {:error, errors()}
  @type schema :: [{field(), [rule()]}]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Registers a list of rules for `field` on `data`. Returns the updated data map.
  Rules are applied in declaration order. Short-circuits within a field on first
  failure; collects errors across all fields.

  `field` can be an atom, a string, or a list of strings (path):

      data
      |> Validate.rule(:title,              [:required, :string])  # atom key
      |> Validate.rule("title",             [:required, :string])  # string key
      |> Validate.rule(["address", "city"], [:required, :string])  # nested path
  """
  @spec rule(validation_data(), field(), [rule()]) :: validation_data()
  def rule(data, field, rules) when is_map(data) and is_list(rules) do
    existing = Map.get(data, @metadata_key, [])
    Map.put(data, @metadata_key, existing ++ [{field, rules}])
  end

  @doc """
  Runs all registered validations. Returns `{:ok, clean_data}` or
  `{:error, [{field, message}, ...]}`.
  """
  @spec run(validation_data()) :: result()
  def run(data) when is_map(data) do
    validations = Map.get(data, @metadata_key, [])
    clean_data = Map.delete(data, @metadata_key)
    run_validations(clean_data, validations)
  end

  @doc "Same as `run/1` but calls `success_fn.(clean_data)` on success."
  @spec run(validation_data(), (validation_data() -> any())) :: any() | result()
  def run(data, success_fn) when is_map(data) and is_function(success_fn, 1) do
    case run(data) do
      {:ok, clean_data} -> success_fn.(clean_data)
      error -> error
    end
  end

  @doc """
  Runs a pre-built schema against `data` directly, without piping through `validate/3`.
  """
  @spec run_schema(validation_data(), schema()) :: result()
  def run_schema(data, schema) when is_map(data) and is_list(schema) do
    run_validations(data, schema)
  end

  @doc """
  Builds a reusable schema from a list of `{field, rules}` tuples.
  Atom keys, string keys, and path keys are all supported:

      @create_user_schema Validate.build_schema([
        {:name,              [:required, :string, {:min_length, 2}]},
        {"email",            [:required, :email]},
        {["address", "city"], [:required, :string]},
        {:age,               [:integer, {:between, 18, 120}]}
      ])

  Atom-only schemas can use the keyword shorthand:

      Validate.build_schema(name: [:required, :string], age: [:required, :integer])
  """
  @spec build_schema([{field(), [rule()]}]) :: schema()
  def build_schema(fields) when is_list(fields), do: fields

  # ---------------------------------------------------------------------------
  # Internal
  # ---------------------------------------------------------------------------

  defp run_validations(data, validations) do
    errors =
      Enum.reduce(validations, %{}, fn {field, rules}, acc ->
        case collect_field_errors(data, field, rules) do
          [] -> acc
          msgs -> Map.update(acc, field, msgs, &(&1 ++ msgs))
        end
      end)

    case errors do
      empty when map_size(empty) == 0 -> {:ok, data}
      _ -> {:error, errors}
    end
  end

  # Short-circuit within a field on first rule failure.
  # Returns a list of message strings (field key is managed by run_validations).
  defp collect_field_errors(data, field, rules) do
    Enum.reduce_while(rules, [], fn rule, _acc ->
      case apply_rule(data, field, rule) do
        :ok -> {:cont, []}
        {:error, msg} -> {:halt, [msg]}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Rules — Presence
  # ---------------------------------------------------------------------------

  defp apply_rule(data, field, :required) do
    if present?(data, field),
      do: :ok,
      else: {:error, "is required"}
  end

  # ---------------------------------------------------------------------------
  # Rules — Type checks
  # ---------------------------------------------------------------------------

  defp apply_rule(data, field, :string) do
    case get_field(data, field) do
      v when is_binary(v) -> :ok
      nil -> :ok
      _ -> {:error, "must be a string"}
    end
  end

  defp apply_rule(data, field, :integer) do
    case get_field(data, field) do
      v when is_integer(v) -> :ok
      nil -> :ok
      _ -> {:error, "must be an integer"}
    end
  end

  defp apply_rule(data, field, :float) do
    case get_field(data, field) do
      v when is_float(v) -> :ok
      nil -> :ok
      _ -> {:error, "must be a float"}
    end
  end

  defp apply_rule(data, field, :number) do
    case get_field(data, field) do
      v when is_number(v) -> :ok
      nil -> :ok
      _ -> {:error, "must be a number"}
    end
  end

  defp apply_rule(data, field, :boolean) do
    case get_field(data, field) do
      v when is_boolean(v) -> :ok
      nil -> :ok
      _ -> {:error, "must be a boolean"}
    end
  end

  # ---------------------------------------------------------------------------
  # Rules — Numeric
  # ---------------------------------------------------------------------------

  defp apply_rule(data, field, :positive) do
    case get_field(data, field) do
      nil -> :ok
      v when is_number(v) and v > 0 -> :ok
      v when is_number(v) -> {:error, "must be positive"}
      _ -> {:error, "must be a number to use :positive"}
    end
  end

  defp apply_rule(data, field, :non_negative) do
    case get_field(data, field) do
      nil -> :ok
      v when is_number(v) and v >= 0 -> :ok
      v when is_number(v) -> {:error, "must be non-negative"}
      _ -> {:error, "must be a number to use :non_negative"}
    end
  end

  defp apply_rule(data, field, {:min, min}) do
    case get_field(data, field) do
      nil -> :ok
      v when is_number(v) and v >= min -> :ok
      v when is_number(v) -> {:error, "must be at least #{min}"}
      _ -> {:error, "must be a number to use :min"}
    end
  end

  defp apply_rule(data, field, {:max, max}) do
    case get_field(data, field) do
      nil -> :ok
      v when is_number(v) and v <= max -> :ok
      v when is_number(v) -> {:error, "must be at most #{max}"}
      _ -> {:error, "must be a number to use :max"}
    end
  end

  defp apply_rule(data, field, {:between, min, max}) do
    case get_field(data, field) do
      nil -> :ok
      v when is_number(v) and v >= min and v <= max -> :ok
      v when is_number(v) -> {:error, "must be between #{min} and #{max}"}
      _ -> {:error, "must be a number to use :between"}
    end
  end

  defp apply_rule(data, field, {:multiple_of, n}) when is_number(n) and n != 0 do
    case get_field(data, field) do
      nil ->
        :ok

      v when is_number(v) ->
        if rem_safe(v, n) == 0, do: :ok, else: {:error, "must be a multiple of #{n}"}

      _ ->
        {:error, "must be a number to use :multiple_of"}
    end
  end

  # ---------------------------------------------------------------------------
  # Rules — String length
  # ---------------------------------------------------------------------------

  defp apply_rule(data, field, {:min_length, len}) do
    case get_field(data, field) do
      nil ->
        :ok

      v when is_binary(v) ->
        if String.length(v) >= len, do: :ok, else: {:error, "must be at least #{len} characters"}

      _ ->
        {:error, "must be a string to use :min_length"}
    end
  end

  defp apply_rule(data, field, {:max_length, len}) do
    case get_field(data, field) do
      nil ->
        :ok

      v when is_binary(v) ->
        if String.length(v) <= len, do: :ok, else: {:error, "must be at most #{len} characters"}

      _ ->
        {:error, "must be a string to use :max_length"}
    end
  end

  defp apply_rule(data, field, {:length, len}) do
    case get_field(data, field) do
      nil ->
        :ok

      v when is_binary(v) ->
        if String.length(v) == len, do: :ok, else: {:error, "must be exactly #{len} characters"}

      _ ->
        {:error, "must be a string to use :length"}
    end
  end

  # ---------------------------------------------------------------------------
  # Rules — String format
  # ---------------------------------------------------------------------------

  defp apply_rule(data, field, :email) do
    case get_field(data, field) do
      nil ->
        :ok

      v when is_binary(v) ->
        if Regex.match?(@email_regex, v), do: :ok, else: {:error, "must be a valid email address"}

      _ ->
        {:error, "must be a string to use :email"}
    end
  end

  defp apply_rule(data, field, :uuid) do
    case get_field(data, field) do
      nil ->
        :ok

      v when is_binary(v) ->
        if Regex.match?(@uuid_regex, v), do: :ok, else: {:error, "must be a valid UUID"}

      _ ->
        {:error, "must be a string to use :uuid"}
    end
  end

  defp apply_rule(data, field, :url) do
    case get_field(data, field) do
      nil ->
        :ok

      v when is_binary(v) ->
        if Regex.match?(@url_regex, v), do: :ok, else: {:error, "must be a valid URL"}

      _ ->
        {:error, "must be a string to use :url"}
    end
  end

  defp apply_rule(data, field, :iso8601) do
    case get_field(data, field) do
      nil ->
        :ok

      v when is_binary(v) ->
        case DateTime.from_iso8601(v) do
          {:ok, _, _} -> :ok
          _ -> {:error, "must be a valid ISO 8601 datetime"}
        end

      _ ->
        {:error, "must be a string to use :iso8601"}
    end
  end

  defp apply_rule(data, field, :date) do
    case get_field(data, field) do
      nil ->
        :ok

      v when is_binary(v) ->
        with true <- Regex.match?(@date_regex, v),
             {:ok, _} <- Date.from_iso8601(v) do
          :ok
        else
          _ -> {:error, "must be a valid date (YYYY-MM-DD)"}
        end

      _ ->
        {:error, "must be a string to use :date"}
    end
  end

  defp apply_rule(data, field, {:regex, %Regex{} = pattern}) do
    case get_field(data, field) do
      nil ->
        :ok

      v when is_binary(v) ->
        if Regex.match?(pattern, v), do: :ok, else: {:error, "has invalid format"}

      _ ->
        {:error, "must be a string to use :regex"}
    end
  end

  defp apply_rule(data, field, :trimmed) do
    case get_field(data, field) do
      nil ->
        :ok

      v when is_binary(v) ->
        if String.trim(v) == v,
          do: :ok,
          else: {:error, "must not have leading or trailing whitespace"}

      _ ->
        {:error, "must be a string to use :trimmed"}
    end
  end

  defp apply_rule(data, field, {:starts_with, prefix}) when is_binary(prefix) do
    case get_field(data, field) do
      nil ->
        :ok

      v when is_binary(v) ->
        if String.starts_with?(v, prefix),
          do: :ok,
          else: {:error, ~s(must start with "#{prefix}")}

      _ ->
        {:error, "must be a string to use :starts_with"}
    end
  end

  defp apply_rule(data, field, {:ends_with, suffix}) when is_binary(suffix) do
    case get_field(data, field) do
      nil ->
        :ok

      v when is_binary(v) ->
        if String.ends_with?(v, suffix), do: :ok, else: {:error, ~s(must end with "#{suffix}")}

      _ ->
        {:error, "must be a string to use :ends_with"}
    end
  end

  # ---------------------------------------------------------------------------
  # Rules — Membership
  # ---------------------------------------------------------------------------

  defp apply_rule(data, field, {:in, allowed}) when is_list(allowed) do
    case get_field(data, field) do
      nil ->
        :ok

      v ->
        if v in allowed,
          do: :ok,
          else:
            {:error, "must be one of: #{allowed |> Enum.map(&to_string/1) |> Enum.join(", ")}"}
    end
  end

  defp apply_rule(data, field, {:not_in, blocked}) when is_list(blocked) do
    case get_field(data, field) do
      nil ->
        :ok

      v ->
        if v not in blocked,
          do: :ok,
          else: {:error, "contains a reserved or blocked value"}
    end
  end

  # ---------------------------------------------------------------------------
  # Rules — Collections
  # ---------------------------------------------------------------------------

  defp apply_rule(data, field, {:list_of, rule}) do
    case get_field(data, field) do
      nil ->
        :ok

      v when is_list(v) ->
        errors =
          v
          |> Enum.with_index()
          |> Enum.flat_map(fn {item, idx} ->
            case apply_rule(%{item: item}, :item, rule) do
              :ok -> []
              {:error, msg} -> ["index #{idx}: #{msg}"]
            end
          end)

        case errors do
          [] -> :ok
          _ -> {:error, Enum.join(errors, "; ")}
        end

      _ ->
        {:error, "must be a list"}
    end
  end

  defp apply_rule(data, field, {:min_items, n}) do
    case get_field(data, field) do
      nil ->
        :ok

      v when is_list(v) ->
        if length(v) >= n, do: :ok, else: {:error, "must have at least #{n} items"}

      _ ->
        {:error, "must be a list to use :min_items"}
    end
  end

  defp apply_rule(data, field, {:max_items, n}) do
    case get_field(data, field) do
      nil ->
        :ok

      v when is_list(v) ->
        if length(v) <= n, do: :ok, else: {:error, "must have at most #{n} items"}

      _ ->
        {:error, "must be a list to use :max_items"}
    end
  end

  defp apply_rule(data, field, {:nested, schema}) when is_map(schema) or is_list(schema) do
    schema_list = if is_map(schema), do: Enum.to_list(schema), else: schema

    case get_field(data, field) do
      nil ->
        :ok

      v when is_map(v) ->
        case run_validations(v, schema_list) do
          {:ok, _} ->
            :ok

          {:error, errs} ->
            msg =
              errs
              |> Enum.map(fn {f, msgs} -> "#{f}: #{Enum.join(msgs, ", ")}" end)
              |> Enum.join("; ")

            {:error, "nested errors — #{msg}"}
        end

      _ ->
        {:error, "must be a map to use :nested"}
    end
  end

  # ---------------------------------------------------------------------------
  # Rules — Cross-field
  # ---------------------------------------------------------------------------

  defp apply_rule(data, field, {:equal_to, other_field}) do
    if get_field(data, field) == get_field(data, other_field),
      do: :ok,
      else: {:error, "must equal #{other_field}"}
  end

  defp apply_rule(data, field, {:greater_than, other_field}) do
    fv = get_field(data, field)
    ov = get_field(data, other_field)

    cond do
      is_nil(fv) or is_nil(ov) -> :ok
      not is_number(fv) -> {:error, "must be a number to use :greater_than"}
      not is_number(ov) -> {:error, "#{other_field} must be a number to use :greater_than"}
      fv > ov -> :ok
      true -> {:error, "must be greater than #{other_field}"}
    end
  end

  defp apply_rule(data, field, {:only_one_of, other_field}) do
    fp = present?(data, field)
    op = present?(data, other_field)

    if fp != op,
      do: :ok,
      else: {:error, "exactly one of #{field} or #{other_field} must be present"}
  end

  defp apply_rule(data, field, {:forbidden_with, other_field}) do
    if present?(data, field) and present?(data, other_field),
      do: {:error, "cannot be present together with #{other_field}"},
      else: :ok
  end

  defp apply_rule(data, field, {:required_if, other_field, value}) do
    if get_field(data, other_field) == value and not present?(data, field),
      do: {:error, "is required when #{other_field} is #{value}"},
      else: :ok
  end

  defp apply_rule(data, field, {:required_with, other_field}) do
    if present?(data, other_field) and not present?(data, field),
      do: {:error, "is required when #{other_field} is present"},
      else: :ok
  end

  # ---------------------------------------------------------------------------
  # Rules — Custom functions
  # ---------------------------------------------------------------------------

  defp apply_rule(data, field, {:fn, func}) when is_function(func, 1) do
    case func.(get_field(data, field)) do
      :ok ->
        :ok

      {:ok, _} ->
        :ok

      {:error, msg} when is_binary(msg) ->
        {:error, msg}

      true ->
        :ok

      false ->
        {:error, "failed custom validation"}

      other ->
        raise ArgumentError,
              "custom validator for #{field} must return :ok | {:ok, v} | {:error, msg} | boolean, got: #{inspect(other)}"
    end
  end

  defp apply_rule(data, field, {:fn, func, msg})
       when is_function(func, 1) and is_binary(msg) do
    case func.(get_field(data, field)) do
      :ok ->
        :ok

      {:ok, _} ->
        :ok

      {:error, _} ->
        {:error, msg}

      true ->
        :ok

      false ->
        {:error, msg}

      other ->
        raise ArgumentError,
              "custom validator for #{field} must return :ok | {:ok, v} | {:error, msg} | boolean, got: #{inspect(other)}"
    end
  end

  # ---------------------------------------------------------------------------
  # Rules — Unknown
  # ---------------------------------------------------------------------------

  defp apply_rule(_data, field, unknown) do
    raise ArgumentError, "unknown validation rule for #{field}: #{inspect(unknown)}"
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp present?(data, field) when is_list(field) do
    not is_nil(get_in(data, field))
  end

  defp present?(data, field) do
    Map.has_key?(data, field) and not is_nil(data[field])
  end

  # Fetches a value by atom key, string key, or list path.
  defp get_field(data, field) when is_atom(field), do: Map.get(data, field)
  defp get_field(data, field) when is_binary(field), do: Map.get(data, field)
  defp get_field(data, path) when is_list(path), do: get_in(data, path)

  defp rem_safe(a, b) when is_integer(a) and is_integer(b), do: rem(a, b)
  defp rem_safe(a, b), do: :math.fmod(a, b)
end
