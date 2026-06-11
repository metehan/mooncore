# Dev Tools

Mooncore includes a built-in development dashboard for real-time observability of your running application. The dashboard is a full-featured single-page app with live VM metrics, action execution, developer tools, and more.

> **Security:** Never enable `mooncore_dev_tools` in production. The dashboard provides full access to eval, action execution, and file system browsing.

## Enabling Dev Mode

Dev tools require two things:

1. **Config flag** — `mooncore_dev_tools: true` in your application config
2. **Secret** — `MOONCORE_DEV_SECRET` environment variable set to a non-empty value

The secret is mandatory: it protects the dashboard and MCP server. Without it the dev server won't start, even if the config flag is set.

```elixir
# config/dev.exs
config :mooncore,
  mooncore_dev_tools: true,
  mcp_port: 4040,                # default, can be changed
  oauth_access_token_ttl_seconds: 1_209_600, # default: 14 days
  dev_tools_allowed_ips: [        # optional IP allowlist
    "127.0.0.1",
    "::1",
    "10.0.0.0/8"
  ]
```

> **IP Allowlist:** If `dev_tools_allowed_ips` is set, only requests from matching IPs are accepted (403 Forbidden otherwise). Supports plain IPs (`"127.0.0.1"`) and CIDR ranges (`"10.0.0.0/8"`). If unset or empty, all IPs are allowed (default behaviour — backwards compatible).

```bash
export MOONCORE_DEV_SECRET=your-secret-here
mix run --no-halt
```

Or inline:

```bash
MOONCORE_DEV_SECRET=your-secret mix run --no-halt
```

When both are configured, a dedicated HTTP server starts on `mcp_port` (default 4040). Open `http://localhost:4040/` in your browser.

When either is missing, nothing dev-related starts — no server, no watcher, no overhead.

MCP clients authenticate through OAuth access tokens. Tokens remain valid for 14 days by
default. Set `oauth_access_token_ttl_seconds` to a positive integer to choose a different
lifetime. These tokens grant the same unrestricted dev-tools access as
`MOONCORE_DEV_SECRET`, so keep the server limited to trusted development networks.

## Dashboard Screens

The dashboard has a left sidebar with eight sections. Below is a detailed walkthrough of each.

---

### Dashboard

The main overview of your running BEAM VM. Auto-refreshes every 2 seconds.

**Overview tab** shows four metric cards with sparkline history charts:

- **Total Memory** — current total memory used by the VM
- **CPU Runtime** — runtime ratio percentage (how busy the VM is)
- **Processes** — number of active Erlang processes
- **Reductions** — total reduction count (measure of work done)

Below the cards:

- **Memory Breakdown** — horizontal bar chart showing memory split across processes, binary, ETS, atom, and code
- **Scheduler Utilization** — per-scheduler CPU percent with color coding (green < 50%, yellow < 80%, red > 80%)
- **VM Limits** — gauge bars for processes, atoms, ports, and ETS tables vs their limits
- **Quick Stats** — runtime, CPU runtime ratio, ETS table count

**Processes tab** — table of the top 20 processes sorted by memory:

| Column           | Description                                 |
| ---------------- | ------------------------------------------- |
| Name / PID       | Registered name (if any) and PID            |
| Memory           | Process heap memory                         |
| MQ               | Message queue length (amber > 0, red > 100) |
| Reductions       | Work done by this process                   |
| Status           | running / waiting / suspended               |
| Current Function | What the process is currently executing     |

**ETS tab** — all ETS tables sorted by memory, showing name, row count, memory, and type (set, ordered_set, bag, etc.).

**Apps tab** — all started OTP applications with name, version, and description.

---

### Api

Lists all registered actions across all your apps, grouped by app.

Each app group shows:
- App name and action module
- Defined roles
- Action count

Each action row shows:
- Action name (e.g. `task.create`)
- Handler function (e.g. `MyApp.Action.Task.create`)
- Access level — **public** (green badge, no roles required) or **protected** (violet badge listing required roles)

---

### Actions (Runner)

Execute any action directly from the browser.

**Fields:**
- **Action** — action name string (e.g. `task.create`)
- **Params (JSON)** — JSON object of parameters to pass
- **Auth (JSON, optional)** — auth context with roles, user, app, etc.

**Buttons:**
- **Run** — executes the action through the full pipeline and shows the JSON result below
- **→ To Eval** — converts the action call to an Elixir `Mooncore.Action.execute(...)` expression and sends it to the Console

When the Actions page is active, the **right panel** shows the **Action Logs** panel (see below).

---

### Tools

A collection of developer utilities, organized in sub-tabs:

**JSON ↔ Elixir** — bidirectional converter between JSON objects and Elixir map syntax. Paste JSON and get `%{"key" => "value"}` map notation, or vice versa. Has a Copy button.

**JWT Token** — two modes:
- **Create Token** — enter claims as JSON (user, app, roles, etc.), generates a signed JWT using your configured RS256 key. Shows the raw token with copy support.
- **Decode Token** — paste a JWT, verify it against your key with **Verify & Decode**, or just decode the payload without verification using **Decode Payload (no verify)**. Shows expiry info (`_expired`, `_exp_human`).

**Base64** — encode/decode with standard and URL-safe variants. Four buttons: Encode, Decode, URL-safe Encode, URL-safe Decode.

**Timestamps** — convert between Unix timestamps and ISO 8601 dates. Auto-detects seconds vs milliseconds. Shows a live "Now" counter. **Use now** button fills both fields with the current time.

**Inspect** — evaluate any Elixir expression and get `inspect/1` output with pretty-printing. Also has a **Type Info** button that shows the type, byte_size (for binaries), and length (for lists/maps).

---

### Guides

A Livebook-style markdown editor for your project's `guides/` directory.

**Guide list** — shows all `.md` files from your project's `guides/` folder with name and filename.

**Guide editor** — split-pane view:
- **Left pane** — CodeMirror editor with markdown syntax highlighting. Supports Ctrl+S / Cmd+S to save.
- **Right pane** — live rendered preview of the markdown content.

Code blocks with `elixir`, `ex`, `exs`, or `iex` language tags get a **▶ Run** button (appears on hover) that evaluates the code in the running application and shows the result inline. You can edit the code in the block before running.

Changes are saved back to the actual file on disk.

---

### Clients

Real-time view of WebSocket connections, grouped by pool/group.

**Header** shows total connection count and total channel count. Auto-refreshes every 3 seconds (toggleable with ⏸/▶ button).

**Groups** — each group is expandable (default: expanded) showing:
- Group name
- PID count
- Channel count

**Channels** — each channel shows its name with an icon:
- `@` prefix (cyan) — user channels
- `#` prefix (violet) — room/topic channels

Click a channel to expand and see individual member PIDs with green connection dots.

---

### Console

An IEx-like REPL running against your live application.

Features:
- Type Elixir expressions and press Enter (or click **Run**) to evaluate
- Results show in green, errors in red, input in violet
- **Command history** — press ↑/↓ arrows to navigate previous commands
- Shift+Enter for multi-line input

Everything evaluates via `Code.eval_string/1` in the running application — treat it like a full IEx session.

Other pages can send code here: the Actions page has a **→ To Eval** button, and the Tools/Inspect page evaluates directly.

---

### Files

A file browser for your project directory.

- Navigate directories by clicking folders
- Click files to open them in the **right panel editor**
- Shows file sizes
- **↑ Up** button to go to parent directory
- Hides dotfiles and `_build`, `deps`, `node_modules`, `.git` directories

**Right panel file editor:**
- CodeMirror editor with syntax highlighting (Elixir, Erlang, JavaScript, HTML, CSS, Markdown, YAML, Shell, etc.)
- Shows language label and file path
- **Save** button (also Ctrl+S / Cmd+S) — writes changes to disk
- **Eval** button — appears for `.ex` and `.exs` files, evaluates the entire file content
- Dirty indicator (amber dot) when there are unsaved changes

---

## Action Logs Panel

The right panel shows **Action Logs** whenever the Actions page is active and no file is open. This is a live feed of all action executions across HTTP, WebSocket, and MCP sources.

Features:
- **Auto-refresh** every 2 seconds (toggleable)
- **Filter** by action name
- **Clear** button to wipe the log buffer
- Each log entry shows: action name, source badge (ws/http), error indicator (✗), and duration in ms

**Expanded entry** shows:
- IP address and timestamp
- **Params** — with Copy JSON and Copy Map (Elixir syntax) buttons
- **Auth** — authentication context used
- **Response** — action result with Copy buttons
- **Load in Runner** — pre-fills the Actions page with this action's name, params, and auth for re-execution
