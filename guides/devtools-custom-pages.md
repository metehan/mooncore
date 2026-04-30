# Custom Pages / Devtools Indicators

A system for apps to create custom dashboard pages with widgets backed by ETS data.

---

## Overview

```
┌─────────────────────────────────────┐
│        Your Application              │
│                                      │
│   ┌──────────┐   ┌──────────────┐  │
│   │ Register │   │ Update Data  │  │
│   │ Pages    │   │ (ETS write)  │  │
│   └──────────┘   └──────────────┘  │
└─────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│      ETS Tables (:mooncore_devtools_*) │
│                                      │
│   pages     - Widget definitions     │
│   metrics   - Key-value numbers     │
│   cols      - List data (maps)       │
│   ts        - Timeseries data        │
└─────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│         Devtools UI                  │
│    (Renders widgets from ETS)        │
└─────────────────────────────────────┘
```

---

## Quick Start

### 1. Enable Devtools

Custom pages only run when devtools are enabled — i.e. when both `config :mooncore, mooncore_dev_tools: true` is set and `MOONCORE_DEV_SECRET` is set.

When either is missing, `Devtools` GenServer won't start and page registration calls become no-ops — so it's safe to leave the setup code in your app.

### 2. Define a Page

```elixir
# In your app's startup or init:
alias Mooncore.Dev.Devtools

Devtools.register_page("My Dashboard", %{
  "header_title" => "My Dashboard",
  "icon" => "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='currentColor'><path d='M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z'/></svg>",
  "widgets" => [
    %{
      "id" => "user_count",
      "type" => "stat",
      "source" => %{"type" => "metric", "key" => "users_total"},
      "options" => %{"show_delta" => true, "unit" => "users"}
    }
  ]
})
```

Avoid using these names for pages,  they are used by default by mooncore: dashboard, api, tools, guides, ets, clients, sockets, console.

**Page-level fields:**

| Field    | Description                                                   |
| -------- | ------------------------------------------------------------- |
| `"icon"` | SVG string for the sidebar menu item (overrides default icon) |

### 3. Update Metrics

```elixir
# Single metric
Mooncore.Dev.Devtools.update_metric("users_total", 12450)

# Bulk update
Mooncore.Dev.Devtools.bulk_update_metrics %{
  "users_total" => 12450,
  "active_sessions" => 342
}
```

### 4. Update Collections (Tables/Lists)

```elixir
Mooncore.Dev.Devtools.update_collection("UserList", [
  %{id: 1, email: "alice@example.com", created_at: ~N[2026-04-01 12:00:00]},
  %{id: 2, email: "bob@example.com", created_at: ~N[2026-04-02 15:30:00]}
])
```

---

## Widget Types

### `"stat"` — Simple metric display

```elixir
 %{
  "name" => "Total Users",
  "type" => "stat",
  "source" => %{"type" => "metric", "key" => "users_total"},
  "row" => "row1",
  "options" => %{
    "show_delta" => true,
    "unit" => "users",
    "icon" => "<svg width='14' height='14' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2'><path d='M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2'/><circle cx='9' cy='7' r='4'/></svg>",
    "color" => "#a78bfa"
  }
}
```

**Options:** `show_delta`, `unit`, `icon` (SVG string or ICONS map key), `color` (CSS color). Non-SVG icon values are looked up in the `ICONS` map (e.g. `"users"` uses the built-in users icon).

### `"key_value"` — Label + value with optional eval

```elixir
%{
  "name" => "System Status",
  "type" => "key_value",
  "source" => %{"type" => "metric", "key" => "status"},
  "row" => "row2",
  "options" => %{
    "color" => "#4ade80"
  }
}
```

### `"table"` — Tabular data with columns and per-row actions

```elixir
%{
  "name" => "Users",
  "type" => "table",
  "source" => %{"type" => "collection", "key" => "UserList"},
  "row" => "row1",
  "columns" => [
    %{"key" => "id", "label" => "ID"},
    %{"key" => "email", "label" => "Email"},
    %{"key" => "status", "label" => "Status"}
  ],
  "evals" => [
    %{
      "label" => "Edit",
      "default_code" => "IO.inspect(item)",
      "confirm" => "Edit this user?"
    },
    %{
      "label" => "Delete",
      "default_code" => "Mooncore.Dev.Devtools.delete_item(item[\"id\"])",
      "confirm" => "Delete this user?"
    }
  ]
}
```

**Per-row eval button** — each row gets action buttons that run Elixir code with `item` bound to that row's data. Useful for CRUD operations.

### `"list"` — Simple list with template and per-item actions

```elixir
%{
  "name" => "Recent Errors",
  "type" => "list",
  "source" => %{"type" => "collection", "key" => "RecentErrors"},
  "row" => "row1",
  "options" => %{
    "item_template" => "[%level%] %id% - %message%",
    "max_items" => 100,
    "color" => "#f87171"
  },
  "evals" => [
    %{
      "label" => "Retry",
      "default_code" => "Mooncore.Actions.retry_error(item[\"id\"])"
    }
  ]
}
```

### `"chart_line"` — Timeseries line chart

```elixir
%{
  "name" => "Payment Volume",
  "type" => "chart_line",
  "source" => %{"type" => "timeseries", "key" => "PaymentsTS"},
  "row" => "row2",
  "options" => %{"color" => "#22d3ee"}
}
```

> **Note:** Chart rendering is a placeholder — `chart_line` displays `(chart placeholder)` until a real chart library is integrated.

### `"html"` — Raw HTML content

```elixir
%{
  "name" => "Custom Content",
  "type" => "html",
  "row" => "row1",
  "template" => "<p>Your static HTML here</p>"
}
```

Renders `widget.template` as raw HTML inside a styled card.

---

## Layout: Rows

Widgets can be placed in rows using the `"row"` field (default: `"row1"`). Widgets in the same row are displayed side-by-side. Rows are sorted alphabetically.

```elixir
"widgets" => [
  %{"name" => "Users", "type" => "stat", "row" => "row1", ...},
  %{"name" => "Sessions", "type" => "stat", "row" => "row1", ...},
  %{"name" => "System", "type" => "key_value", "row" => "row2", ...}
]
```

Result: row1 shows Users + Sessions side-by-side, row2 shows System below.

---

## Data Sources

| Source         | Example                                            | Description                                                   |
| -------------- | -------------------------------------------------- | ------------------------------------------------------------- |
| `"metric"`     | `%{"type" => "metric", "key" => "users_total"}`    | Single key-value                                              |
| `"collection"` | `%{"type" => "collection", "key" => "UserList"}`   | List of maps                                                  |
| `"timeseries"` | `%{"type" => "timeseries", "key" => "PaymentsTS"}` | List of `%{ts, value}`                                        |
| `"metric_map"` | `%{"type" => "metric_map", "key" => "Summary"}`    | All metrics as flat map (direct ETS access, not via HTTP API) |

---

## API Reference

### Writing Data

```elixir
# Metrics
Mooncore.Dev.Devtools.update_metric(key, value)
Mooncore.Dev.Devtools.bulk_update_metrics(%{"key" => value})
Mooncore.Dev.Devtools.delete_metric(key)

# Collections
Mooncore.Dev.Devtools.update_collection(name, items)
Mooncore.Dev.Devtools.delete_collection(name)

# Timeseries
Mooncore.Dev.Devtools.update_timeseries(name, [%{ts: 123, value: 456}])

# Bulk
Mooncore.Dev.Devtools.bulk_update_collections(%{"Users" => [...]})
```

### Reading Data

```elixir
# Single metric
Mooncore.Dev.Devtools.get_metric("users_total")
# => {:ok, 12450} or {:error, :not_found}

# Single collection
Mooncore.Dev.Devtools.get_collection("UserList")

# Timeseries
Mooncore.Dev.Devtools.get_timeseries("PaymentsTS")
```

### Managing Pages

```elixir
# Register a page
Mooncore.Dev.Devtools.register_page("Dashboard", page_def)

# Get all pages
Mooncore.Dev.Devtools.get_pages()
# => [{"Dashboard", %{...}}, ...]

# Get single page
Mooncore.Dev.Devtools.get_page("Dashboard")

# Remove a page
Mooncore.Dev.Devtools.unregister_page("Dashboard")
```

---

## Eval Feature

Elixir code can be run against row/item data via the `evals` array on table and list widgets. Each eval action has:

| Field            | Description                                               |
| ---------------- | --------------------------------------------------------- |
| `"label"`        | Button label shown in the UI                              |
| `"default_code"` | Elixir code to run — `item` is bound to the row/item data |
| `"confirm"`      | Optional confirmation message before running              |

### Backend requirement

The eval endpoint (`POST /api/devtools/eval`) binds `item` to the row/item map passed in the request. Code runs via `Code.eval_string/2` with no other context automatically available — eval code must be self-contained or rely on fully-qualified calls:

```elixir
"default_code" => "Enum.filter(item[\"children\"], &(&1[\"active\"] == true))"
"default_code" => "PortModels.retry_error(item[\"id\"])"
```

> **Note:** Eval runs directly in the live application — use only on internal/dev dashboards. No sandbox.

---

## Example: Complete Dashboard Setup

```elixir
defmodule MyApp.Setup do
  alias Mooncore.Dev.Devtools

  def init_devtools do
    # Register pages
    Devtools.register_page("Analytics", %{
      "header_title" => "Analytics",
      "widgets" => [
        %{
          "id" => "total_users",
          "type" => "stat",
          "source" => %{"type" => "metric", "key" => "users_total"},
          "options" => %{"show_delta" => true, "unit" => "users"}
        },
        %{
          "id" => "users_table",
          "type" => "table",
          "source" => %{"type" => "collection", "key" => "UserList"},
          "columns" => [
            %{"key" => "id", "label" => "ID"},
            %{"key" => "email", "label" => "Email"}
          ],
          "evals" => [
            %{"label" => "View", "default_code" => "item"},
            %{"label" => "Edit", "default_code" => "MyApp.edit_user(item[\"id\"])", "confirm" => "Edit this user?"}
          ]
        },
        %{
          "id" => "recent_logs",
          "type" => "list",
          "source" => %{"type" => "collection", "key" => "Logs"},
          "options" => %{"item_template" => "%id% - %message%"},
          "evals" => [
            %{"label" => "Retry", "default_code" => "MyApp.retry_log(item[\"id\"])"}
          ]
        }
      ]
    })

    # Seed initial data
    Devtools.bulk_update_metrics %{
      "users_total" => 0
    }

    Devtools.update_collection("UserList", [])
    Devtools.update_collection("Logs", [])
  end
end
```

---

## Removing

To remove this system:

1. Delete `lib/mooncore/dev/devtools.ex`
2. Remove `{Mooncore.Dev.Devtools, []}` from `application.ex`
3. Remove API routes from `lib/mooncore/dev/plug.ex` (the `/api/devtools/*` routes)

---

## Notes

- All ETS tables are named `:mooncore_devtools_*`
- Data is stored in ETS, not in a database
- No real-time push — UI polls or refreshes manually
- Page definitions are dynamic (runtime, not config)
