defmodule Mooncore.Dev.Devtools do
  @moduledoc """
  Custom pages/devtools indicators system.

  Data lives in ETS tables:
  - `:mooncore_devtools_pages`   - Page/widget definitions
  - `:mooncore_devtools_metrics` - Key-value metrics
  - `:mooncore_devtools_cols`    - Collection data (lists)
  - `:mooncore_devtools_ts`      - Timeseries data

  All updates go through this module. UI is a pure renderer.
  """

  use GenServer

  # ── ETS table names ──────────────────────────────────────

  @pages_table :mooncore_devtools_pages
  @metrics_table :mooncore_devtools_metrics
  @cols_table :mooncore_devtools_cols
  @ts_table :mooncore_devtools_ts

  # ── Client API ───────────────────────────────────────────

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # Metrics
  def update_metric(key, value) do
    GenServer.cast(__MODULE__, {:update_metric, key, value})
  end

  def get_metric(key) do
    case :ets.lookup(@metrics_table, key) do
      [{^key, value}] -> {:ok, value}
      [] -> {:error, :not_found}
    end
  end

  def delete_metric(key) do
    GenServer.cast(__MODULE__, {:delete_metric, key})
  end

  # Collections
  def update_collection(name, items) do
    GenServer.cast(__MODULE__, {:update_collection, name, items})
  end

  def get_collection(name) do
    case :ets.lookup(@cols_table, name) do
      [{^name, items}] -> {:ok, items}
      [] -> {:error, :not_found}
    end
  end

  def delete_collection(name) do
    GenServer.cast(__MODULE__, {:delete_collection, name})
  end

  # Timeseries
  def update_timeseries(name, data_points) do
    GenServer.cast(__MODULE__, {:update_timeseries, name, data_points})
  end

  def get_timeseries(name) do
    case :ets.lookup(@ts_table, name) do
      [{^name, data}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  # Bulk updates
  def bulk_update_metrics(map) when is_map(map) do
    GenServer.cast(__MODULE__, {:bulk_update_metrics, map})
  end

  def bulk_update_collections(map) when is_map(map) do
    GenServer.cast(__MODULE__, {:bulk_update_collections, map})
  end

  # Page definitions
  def register_page(page_name, page_def) do
    GenServer.cast(__MODULE__, {:register_page, page_name, page_def})
  end

  def unregister_page(page_name) do
    GenServer.cast(__MODULE__, {:unregister_page, page_name})
  end

  # Convert source tuple to JSON-safe map (for compatibility with stored tuples)
  # Called on READ to normalize legacy tuple format
  defp normalize_source({type, key}), do: %{"type" => type, "key" => key}
  defp normalize_source(m) when is_map(m), do: m

  defp normalize_widget(w) do
    w
    |> Map.update!("type", &to_string/1)
    |> Map.update!("source", &normalize_source/1)
    |> maybe_normalize_columns()
  end

  defp maybe_normalize_columns(w) do
    if Map.has_key?(w, "columns") do
      Map.update!(w, "columns", fn cols ->
        Enum.map(cols, fn col ->
          Map.update!(col, "key", fn k -> to_string(k) end)
        end)
      end)
    else
      w
    end
  end

  defp normalize_page_def(defn) do
    defn
    |> Map.update!("widgets", fn widgets -> Enum.map(widgets, &normalize_widget/1) end)
    |> then(fn d ->
      if Map.has_key?(d, "icon"), do: Map.update!(d, "icon", &to_string/1), else: d
    end)
  end

  # Get all pages - normalize on read so stored format stays flexible
  def get_pages do
    :ets.tab2list(@pages_table)
    |> Enum.map(fn {name, defn} -> {name, normalize_page_def(defn)} end)
  end

  def get_page(page_name) do
    case :ets.lookup(@pages_table, page_name) do
      [{^page_name, defn}] -> {:ok, normalize_page_def(defn)}
      [] -> {:error, :not_found}
    end
  end

  # Get all data for a source
  def get_data(source) do
    case source do
      {:metric, key} -> get_metric(key)
      {:collection, name} -> get_collection(name)
      {:timeseries, name} -> get_timeseries(name)
      {:metric_map, name} -> get_metric_map(name)
    end
  end

  # Metric map for html widget (%key% substitution)
  defp get_metric_map(name) do
    metrics = :ets.tab2list(@metrics_table) |> Enum.into(%{})
    {:ok, Map.get(metrics, name, %{})}
  end

  # ── GenServer callbacks ──────────────────────────────────

  @impl true
  def init(_opts) do
    :ets.new(@pages_table, [:named_table, :public, read_concurrency: true])
    :ets.new(@metrics_table, [:named_table, :public, read_concurrency: true])
    :ets.new(@cols_table, [:named_table, :public, read_concurrency: true])
    :ets.new(@ts_table, [:named_table, :public, read_concurrency: true])

    {:ok, %{}}
  end

  @impl true
  def handle_cast({:update_metric, key, value}, state) do
    :ets.insert(@metrics_table, {key, value})
    {:noreply, state}
  end

  def handle_cast({:delete_metric, key}, state) do
    :ets.delete(@metrics_table, key)
    {:noreply, state}
  end

  def handle_cast({:update_collection, name, items}, state) do
    :ets.insert(@cols_table, {name, items})
    {:noreply, state}
  end

  def handle_cast({:delete_collection, name}, state) do
    :ets.delete(@cols_table, name)
    {:noreply, state}
  end

  def handle_cast({:update_timeseries, name, data_points}, state) do
    :ets.insert(@ts_table, {name, data_points})
    {:noreply, state}
  end

  def handle_cast({:bulk_update_metrics, map}, state) do
    entries = map |> Enum.map(fn {k, v} -> {k, v} end)
    :ets.insert(@metrics_table, entries)
    {:noreply, state}
  end

  def handle_cast({:bulk_update_collections, map}, state) do
    entries = map |> Enum.map(fn {k, v} -> {k, v} end)
    :ets.insert(@cols_table, entries)
    {:noreply, state}
  end

  def handle_cast({:register_page, page_name, page_def}, state) do
    :ets.insert(@pages_table, {page_name, page_def})
    {:noreply, state}
  end

  def handle_cast({:unregister_page, page_name}, state) do
    :ets.delete(@pages_table, page_name)
    {:noreply, state}
  end
end
