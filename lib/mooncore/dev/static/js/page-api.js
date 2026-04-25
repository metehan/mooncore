/* ─── Api Page — two-panel: left toggles actions/logs, right is runner ─── */
function ApiPage({ pendingLoad, onConsumePendingLoad, onToEval }) {
  const [actions, setActions] = useState([]);
  const [apps, setApps] = useState([]);
  const [loading, setLoading] = useState(true);
  const [leftTab, setLeftTab] = useState('actions'); // 'actions' | 'logs'
  const [filterText, setFilterText] = useState('');
  const [filterRole, setFilterRole] = useState('');
  const [selected, setSelected] = useState(null);
  const [params, setParams] = useState('{}');
  const [auth, setAuth] = useState('');
  const [result, setResult] = useState(null);
  const [running, setRunning] = useState(false);

  useEffect(() => {
    Promise.all([
      api('/api/actions').then(d => d.actions || []),
      api('/api/apps').then(d => d.apps || [])
    ]).then(([a, ap]) => { setActions(a); setApps(ap); setLoading(false); });
  }, []);

  useEffect(() => {
    if (pendingLoad) {
      const match = actions.find(a => a.action === pendingLoad.action);
      setSelected(match || { action: pendingLoad.action });
      setParams(pendingLoad.params);
      setAuth(pendingLoad.auth || '');
      setResult(null);
      onConsumePendingLoad();
    }
  }, [pendingLoad, actions]);

  const appMap = {};
  apps.forEach(a => { appMap[a.key] = a; });

  const allRoles = useMemo(() => {
    const roles = new Set();
    actions.forEach(a => { (a.roles || []).forEach(r => roles.add(r)); });
    return Array.from(roles).sort();
  }, [actions]);

  const filteredActions = useMemo(() => {
    return actions.filter(a => {
      if (filterText) {
        const q = filterText.toLowerCase();
        if (!a.action.toLowerCase().includes(q) && !(a.handler || '').toLowerCase().includes(q)) return false;
      }
      if (filterRole === 'public') { if (!a.public) return false; }
      else if (filterRole) { if (a.public || !(a.roles || []).includes(filterRole)) return false; }
      return true;
    });
  }, [actions, filterText, filterRole]);

  const grouped = useMemo(() => {
    const g = {};
    filteredActions.forEach(a => {
      const k = a.app || 'unknown';
      if (!g[k]) g[k] = [];
      g[k].push(a);
    });
    return g;
  }, [filteredActions]);

  function selectAction(a) {
    setSelected(a);
    setResult(null);
    let p = {};
    if (a.overrides && typeof a.overrides === 'object') Object.entries(a.overrides).forEach(([k, v]) => { p[k] = v; });
    if (Array.isArray(a.validate)) {
      a.validate.forEach(({ name, rules }) => {
        if ((rules || []).includes('required')) p[name] = '';
      });
    }
    setParams(Object.keys(p).length ? JSON.stringify(p, null, 2) : '{}');
    setAuth('');
  }

  async function run() {
    if (!selected) return;
    setRunning(true);
    let p = {}, a = null;
    try { p = JSON.parse(params); } catch (e) { setResult({ error: 'Invalid params JSON' }); setRunning(false); return; }
    if (auth.trim()) { try { a = JSON.parse(auth); } catch (e) { setResult({ error: 'Invalid auth JSON' }); setRunning(false); return; } }
    const r = await api('/api/action', { body: { action: selected.action, params: p, auth: a } });
    setResult(r);
    setRunning(false);
  }

  function replayFromLogs(data) {
    const match = actions.find(a => a.action === data.action);
    setSelected(match || { action: data.action });
    setParams(data.params ? JSON.stringify(data.params, null, 2) : '{}');
    setAuth(data.auth ? JSON.stringify(data.auth, null, 2) : '');
    setResult(null);
  }

  if (loading) return html`<div class="p-8"><span class="spinner"></span></div>`;

  const ic = 'w-full px-3 py-2 bg-gray-950 border border-gray-800 text-xs text-gray-200 font-mono rounded';
  const tabBtn = active => `px-3 py-1.5 text-xs border-none cursor-pointer transition-colors rounded-sm
    ${active ? 'bg-violet-500/15 text-violet-300' : 'bg-transparent text-gray-500 hover:text-gray-300'}`;

  return html`
<div class="h-full flex overflow-hidden">

  <!-- Left panel -->
  <div class="flex flex-col border-r border-gray-800 overflow-hidden" style="width:38%;min-width:220px">

    <!-- Tab bar -->
    <div class="flex items-center gap-1 px-2 py-1.5 border-b border-gray-800 bg-gray-900/40">
      <button class=${tabBtn(leftTab === 'actions')} onClick=${() => setLeftTab('actions')}>Actions</button>
      <button class=${tabBtn(leftTab === 'logs')} onClick=${() => setLeftTab('logs')}>Logs</button>
    </div>

    <!-- Actions tab -->
    ${leftTab === 'actions' && html`
      <div class="px-2 py-1.5 border-b border-gray-800 flex gap-1.5">
        <input class="flex-1 bg-gray-950 border border-gray-800 rounded px-2 py-1 text-xs text-gray-200"
          placeholder="Filter…" value=${filterText} onInput=${e => setFilterText(e.target.value)} />
        <select class="bg-gray-950 border border-gray-800 rounded px-2 py-1 text-xs text-gray-300"
          value=${filterRole} onChange=${e => setFilterRole(e.target.value)}>
          <option value="">all</option>
          <option value="public">public</option>
          ${allRoles.map(r => html`<option key=${r} value=${r}>${r}</option>`)}
        </select>
      </div>
      <div class="flex-1 overflow-y-auto">
        ${Object.entries(grouped).map(([appKey, appActions]) => {
    const app = appMap[appKey];
    return html`
            <div key=${appKey}>
              <div class="px-3 py-1.5 bg-gray-900/60 border-b border-gray-800 sticky top-0 flex items-center gap-2">
                <span class="text-xs font-semibold text-gray-400">${app ? app.name : appKey}</span>
                <span class="text-xs text-gray-600">${appActions.length}</span>
              </div>
              ${appActions.map(a => html`
                <div key=${a.action}
                  class="px-3 py-2 border-b border-gray-800/30 cursor-pointer flex items-center gap-2 transition-colors
                    ${selected && selected.action === a.action ? 'bg-violet-500/10' : 'hover:bg-gray-800/30'}"
                  onClick=${() => selectAction(a)}>
                  <span class="text-xs font-mono ${selected && selected.action === a.action ? 'text-violet-300' : 'text-violet-400'} truncate flex-1">${a.action}</span>
                  ${a.public
        ? html`<span class="text-xs text-emerald-600 shrink-0">pub</span>`
        : html`<span class="text-xs text-gray-600 shrink-0">${(a.roles || []).join(' ')}</span>`}
                </div>
              `)}
            </div>
          `;
  })}
        ${filteredActions.length === 0 && html`<div class="p-5 text-xs text-gray-600">No actions match.</div>`}
      </div>
    `}

    <!-- Logs tab -->
    ${leftTab === 'logs' && html`
      <${ActionLogsPanel} onReplay=${replayFromLogs} />
    `}
  </div>

  <!-- Right: runner -->
  <div class="flex-1 flex flex-col overflow-hidden">
    ${!selected ? html`
      <div class="flex-1 flex items-center justify-center text-xs text-gray-700">Select an action</div>
    ` : html`
      <div class="flex-1 flex flex-col overflow-y-auto">
        <div class="px-5 py-3 border-b border-gray-800">
          <div class="mb-0.5">
            <code class="text-violet-400 text-sm font-bold">${selected.action}</code>
          </div>
          <div class="text-xs text-gray-600 font-mono truncate mb-0.5">${selected.handler}</div>
          <div class="text-xs text-gray-500">
            ${selected.public
        ? html`<span class="text-emerald-700">public</span>`
        : (selected.roles || []).map(r => html`<span class="mr-1.5">${r}</span>`)}
          </div>
        </div>

        <div class="p-5 space-y-4">
          ${selected.validate && selected.validate.length > 0 && html`
            <div>
              <div class="text-xs text-gray-600 mb-2 uppercase tracking-wider">Schema</div>
              <div class="rounded border border-gray-800 overflow-hidden">
                ${selected.validate.map(({ name, rules }) => {
          const req = (rules || []).includes('required');
          const other = (rules || []).filter(r => r !== 'required');
          return html`
                    <div class="flex items-baseline gap-3 px-3 py-1.5 border-b border-gray-800/50 last:border-0">
                      <span class="font-mono text-xs text-gray-300 shrink-0">${name}${req ? html`<span class="text-amber-500">*</span>` : ''}</span>
                      <span class="text-xs text-gray-600 flex flex-wrap gap-1">
                        ${other.map(r => {
            const label = typeof r === 'string' ? r
              : (typeof r === 'object' && r && !r.nested) ? Object.entries(r).map(([k, v]) => `${k}:${JSON.stringify(v)}`).join(' ')
                : null;
            if (!label) return null;
            return html`<span class="font-mono">${label}</span>`;
          })}
                        ${other.filter(r => typeof r === 'object' && r && r.nested).map(r =>
            html`<span class="text-gray-700">nested(${r.nested.map(f => f.name).join(',')})</span>`
          )}
                      </span>
                    </div>`;
        })}
              </div>
            </div>
          `}

          ${selected.overrides && Object.keys(selected.overrides).length > 0 && html`
            <div class="text-xs text-gray-600">
              <span class="text-gray-500">overrides:</span>
              <code class="ml-2 text-amber-500/70">${JSON.stringify(selected.overrides)}</code>
            </div>
          `}

          <div>
            <label class="block text-xs text-gray-500 mb-1">Params (JSON)</label>
            <textarea class=${ic} rows="6" value=${params} onInput=${e => setParams(e.target.value)}></textarea>
          </div>

          <div>
            <label class="block text-xs text-gray-500 mb-1">Auth <span class="text-gray-700">(optional)</span></label>
            <textarea class=${ic} rows="2" value=${auth} onInput=${e => setAuth(e.target.value)}
              placeholder='{"roles":["user"]}'></textarea>
          </div>

          <div class="flex gap-2">
            <button class="px-4 py-1.5 bg-violet-600 hover:bg-violet-700 text-white text-xs rounded cursor-pointer border-none transition-colors"
              onClick=${run} disabled=${running}>
              ${running ? html`<span class="spinner mr-1"></span>` : ''}Run
            </button>
            <button class="px-4 py-1.5 bg-gray-800 hover:bg-gray-700 text-gray-300 text-xs rounded cursor-pointer border-none transition-colors"
              onClick=${() => onToEval(selected.action, params, auth)}>
              → Eval
            </button>
          </div>

          ${result != null && html`
            <div class="rounded border ${result.error || result.ok === false ? 'border-red-900/50' : 'border-gray-800'} overflow-hidden">
              <div class="px-3 py-1.5 border-b ${result.error || result.ok === false ? 'border-red-900/50 bg-red-900/10' : 'border-gray-800 bg-gray-900/50'}">
                <span class="text-xs ${result.error || result.ok === false ? 'text-red-400' : 'text-emerald-400'}">${result.error || result.ok === false ? 'error' : 'ok'}</span>
              </div>
              <pre class="text-xs text-gray-300 p-3 overflow-auto whitespace-pre-wrap">${JSON.stringify(result, null, 2)}</pre>
            </div>
          `}
        </div>
      </div>
    `}
  </div>
</div>
  `;
}

/* ─── JSON to Elixir map converter ─── */
function jsonToElixir(val) {
  if (val === null || val === undefined) return 'nil';
  if (typeof val === 'boolean') return val ? 'true' : 'false';
  if (typeof val === 'number') return String(val);
  if (typeof val === 'string') return '"' + val.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
  if (Array.isArray(val)) return '[' + val.map(jsonToElixir).join(', ') + ']';
  if (typeof val === 'object') {
    const entries = Object.entries(val).map(([k, v]) => '"' + k + '" => ' + jsonToElixir(v));
    return '%{' + entries.join(', ') + '}';
  }
  return 'nil';
}

function buildElixirCall(action, paramsJson, authJson) {
  let p = {};
  try { p = JSON.parse(paramsJson); } catch (e) { p = {}; }
  let req = '%{params: ' + jsonToElixir(p) + '}';
  if (authJson && authJson.trim()) {
    let a = null;
    try { a = JSON.parse(authJson); } catch (e) { }
    if (a) req = '%{params: ' + jsonToElixir(p) + ', auth: ' + jsonToElixir(a) + '}';
  }
  return 'Mooncore.Action.execute("' + action + '", ' + req + ')';
}
