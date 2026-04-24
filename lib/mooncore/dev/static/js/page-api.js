function DashApps({ apps }) {
  return html`
  <div >
  <table>
    <thead>
      <tr class="border-b border-gray-800 bg-gray-900/50">
        <th class="px-4 py-2 text-xs text-gray-500 font-medium">Application</th>
        <th class="px-4 py-2 text-xs text-gray-500 font-medium">Version</th>
        <th class="px-4 py-2 text-xs text-gray-500 font-medium">Description</th>
      </tr>
    </thead>
    <tbody>
      ${(apps || []).map((a, i) => html`
        <tr key=${i} class="border-b border-gray-800/40 hover:bg-gray-800/30 transition-colors">
          <td class="px-4 py-2 text-xs font-mono text-violet-400">${a.name}</td>
          <td class="px-4 py-2 text-xs text-gray-400 font-mono">${a.version}</td>
          <td class="px-4 py-2 text-xs text-gray-500">${a.description}</td>
        </tr>
      `)}
    </tbody>
  </table>
</div>
  `;
}

function DashTopology({ topology }) {
  if (!topology) {
    return html`<div class="p-5 text-sm text-gray-600">Topology data unavailable.</div>`;
  }

  return html`
  <div class="p-5 space-y-5">
    <div class="grid grid-cols-3 gap-4">
      <div class="bg-gray-900 border border-gray-800 rounded-lg p-4">
        <div class="text-xs text-gray-500">Root Supervisors</div>
        <div class="text-xl font-bold text-gray-200 mt-1">${topology.root_count || 0}</div>
      </div>
      <div class="bg-gray-900 border border-gray-800 rounded-lg p-4">
        <div class="text-xs text-gray-500">Registered Supervisors</div>
        <div class="text-xl font-bold text-gray-200 mt-1">${topology.supervisor_count || 0}</div>
      </div>
      <div class="bg-gray-900 border border-gray-800 rounded-lg p-4">
        <div class="text-xs text-gray-500">Registered Processes</div>
        <div class="text-xl font-bold text-gray-200 mt-1">${topology.registered_processes || 0}</div>
      </div>
    </div>

    <div class="bg-gray-900 border border-gray-800 rounded-lg overflow-hidden">
      <div class="px-4 py-3 border-b border-gray-800 flex items-center justify-between">
        <span class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Supervisor Tree</span>
        <span class="text-xs text-gray-600">GenServer, GenStateMachine, and event manager state previews are best-effort snapshots.</span>
      </div>
      <div class="p-4 space-y-3">
        ${(topology.roots || []).length === 0
      ? html`<div class="text-sm text-gray-600">No registered supervisors found.</div>`
      : (topology.roots || []).map((node, index) => html`<${TopologyNode} key=${index} node=${node} depth=${0} />`)
    }
      </div>
    </div>
  </div>
  `;
}

function TopologyNode({ node, depth }) {
  const children = node.children || [];
  const isSupervisor = node.kind === 'supervisor';
  const kindTone =
    node.kind === 'gen_server' ? 'text-cyan-400' :
      node.kind === 'gen_statem' ? 'text-emerald-400' :
        node.kind === 'gen_event' ? 'text-amber-400' :
          isSupervisor ? 'text-violet-400' : 'text-gray-400';

  return html`
  <details class="border border-gray-800 rounded-lg bg-gray-950/60" open=${depth < 2}>
    <summary class="px-3 py-2 cursor-pointer list-none flex items-start gap-3">
      <span class="text-gray-600 text-xs mt-0.5">${children.length > 0 ? '▾' : '•'}</span>
      <div class="flex-1 min-w-0 space-y-1">
        <div class="flex flex-wrap items-center gap-2">
          <span class="text-sm font-mono ${isSupervisor ? 'text-violet-400' : 'text-gray-200'}">${node.label || node.id || node.pid || 'unknown'}</span>
          <span class="text-xs ${kindTone}">${node.kind}</span>
          ${node.restart_strategy && html`<span class="text-xs text-gray-600">${node.restart_strategy}</span>`}
          ${node.status && html`<span class="text-xs text-gray-600">${node.status}</span>`}
          ${node.cycle && html`<span class="text-xs text-amber-400">cycle</span>`}
        </div>
        <div class="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-gray-600 font-mono">
          ${node.pid && html`<span>${node.pid}</span>`}
          ${node.modules && html`<span>${node.modules}</span>`}
          ${node.message_queue_len != null && html`<span>mq ${node.message_queue_len}</span>`}
          ${node.current_function && html`<span>${node.current_function}</span>`}
          ${node.counts && node.counts.active != null && html`<span>${node.counts.active}/${node.counts.specs} active</span>`}
        </div>
      </div>
    </summary>

    ${(node.state_preview || children.length > 0) && html`
      <div class="px-3 pb-3 space-y-3">
        ${node.state_preview && html`
          <div>
            <div class="text-xs text-gray-600 mb-1">State</div>
            <pre class="text-xs text-emerald-400 bg-gray-950 p-2 overflow-x-auto whitespace-pre-wrap">${node.state_preview}</pre>
          </div>
        `}

        ${children.length > 0 && html`
          <div class="pl-3 border-l border-gray-800 space-y-3">
            ${children.map((child, index) => html`<${TopologyNode} key=${index} node=${child} depth=${depth + 1} />`)}
          </div>
        `}
      </div>
    `}
  </details>
  `;
}

/* ─── Api Page (actions list) ─── */
function ApiPage({ loadToRunner }) {
  const [actions, setActions] = useState([]);
  const [apps, setApps] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filterText, setFilterText] = useState('');
  const [filterRole, setFilterRole] = useState('');
  useEffect(() => {
    Promise.all([
      api('/api/actions').then(d => d.actions || []),
      api('/api/apps').then(d => d.apps || [])
    ]).then(([a, ap]) => { setActions(a); setApps(ap); setLoading(false); });
  }, []);
  if (loading) return html`<div class="p-8"> <span class="spinner"></span></div> `;

  // Group actions by app
  const appMap = {};
  apps.forEach(a => { appMap[a.key] = a; });
  const grouped = {};
  actions.forEach(a => {
    const key = a.app || 'unknown';
    if (!grouped[key]) grouped[key] = [];
    grouped[key].push(a);
  });

  // Collect all unique roles for the filter dropdown
  const allRoles = useMemo(() => {
    const roles = new Set();
    actions.forEach(a => { (a.roles || []).forEach(r => roles.add(r)); });
    return Array.from(roles).sort();
  }, [actions]);

  const filteredGrouped = useMemo(() => {
    const result = {};
    Object.entries(grouped).forEach(([appKey, appActions]) => {
      const filtered = appActions.filter(a => {
        // Text filter: match action name or handler
        if (filterText) {
          const q = filterText.toLowerCase();
          if (!a.action.toLowerCase().includes(q) && !(a.handler || '').toLowerCase().includes(q)) {
            return false;
          }
        }
        // Role filter
        if (filterRole === 'public') {
          if (!a.public) return false;
        } else if (filterRole) {
          if (a.public || !(a.roles || []).includes(filterRole)) return false;
        }
        return true;
      });
      if (filtered.length > 0) result[appKey] = filtered;
    });
    return result;
  }, [grouped, filterText, filterRole]);

  const totalFiltered = Object.values(filteredGrouped).reduce((sum, arr) => sum + arr.length, 0);

  return html`
  <div class="h-full flex flex-col">
  <${SectionHeader} title="Api" count=${totalFiltered} />
  <div class="px-4 py-2 border-b border-gray-800 flex items-center gap-2 bg-gray-900/30">
    <input class="flex-1 bg-gray-950 border border-gray-800 rounded px-3 py-1.5 text-xs text-gray-200"
      placeholder="Filter by name or handler..." value=${filterText} onInput=${e => setFilterText(e.target.value)} />
    <select class="bg-gray-950 border border-gray-800 rounded px-2 py-1.5 text-xs text-gray-300"
      value=${filterRole} onChange=${e => setFilterRole(e.target.value)}>
      <option value="">All roles</option>
      <option value="public">public</option>
      ${allRoles.map(r => html`<option key=${r} value=${r}>${r}</option>`)}
    </select>
  </div>
  <div class="flex-1 overflow-y-auto">
    ${Object.entries(filteredGrouped).map(([appKey, appActions]) => {
    const app = appMap[appKey];
    return html`
        <div key=${appKey}>
          <div class="px-5 py-2 bg-gray-900/30 border-b border-gray-800 flex items-center gap-3">
            <span class="text-xs font-semibold text-gray-300">${app ? app.name : appKey}</span>
            <span class="text-xs bg-gray-800 text-gray-500 px-1.5 py-0.5 rounded-full">${appActions.length}</span>
            ${app && html`<span class="text-xs text-gray-600 font-mono">${app.action_module}</span>`}
            ${app && app.roles && app.roles.length > 0 && html`
              <span class="text-xs text-gray-600">roles: ${app.roles.join(', ')}</span>
            `}
          </div>
          <table>
            <tbody>
              ${appActions.map(a => html`
                <tr class="border-b border-gray-800/40 hover:bg-gray-800/30 transition-colors cursor-pointer"
                  onClick=${() => loadToRunner(a)} title="Click to fill in the action runner">
                  <td class="px-5 py-2.5"><code class="text-violet-400 text-xs">${a.action}</code></td>
                  <td class="px-5 py-2.5 text-xs text-gray-600 font-mono">${a.handler}</td>
                  <td class="px-5 py-2.5">
                    ${a.public
        ? html`<span class="text-xs px-1.5 py-0.5 rounded bg-emerald-500/10 text-emerald-400">public</span>`
        : html`<span class="text-xs px-1.5 py-0.5 rounded bg-violet-500/10 text-violet-400">${(a.roles || []).join(', ')}</span>`}
                  </td>
                  <td class="px-5 py-2.5">
                    ${a.validate && a.validate.length > 0
        ? html`<span class="text-xs px-1.5 py-0.5 rounded bg-amber-500/10 text-amber-400">${a.validate.length} field${a.validate.length > 1 ? 's' : ''}</span>`
        : html`<span class="text-xs text-gray-700">—</span>`}
                  </td>
                  <td class="px-5 py-2.5 text-xs text-gray-600 font-mono">
                    ${a.arity || '?'}
                  </td>
                </tr>
                ${(a.overrides && Object.keys(a.overrides).length > 0) && html`
                <tr class="border-b border-gray-800/40 bg-gray-900/20">
                  <td colspan="5" class="px-5 py-1.5 text-xs text-gray-600">
                    <span class="text-gray-500">overrides:</span>
                    <code class="text-amber-400/70 ml-2">${JSON.stringify(a.overrides)}</code>
                  </td>
                </tr>
                `}
                ${a.validate && a.validate.length > 0 && html`
                <tr class="border-b border-gray-800/40 bg-gray-900/20">
                  <td colspan="5" class="px-5 py-1.5 text-xs">
                    <span class="text-gray-500">validate:</span>
                    <span class="ml-2 text-gray-400">${a.validate.map(([field, rules]) => {
          const required = rules.includes(':required');
          return html`<span class="inline-flex items-center gap-0.5 mr-1.5 text-gray-300"><span class="font-mono">${field}</span>${required ? html`<span class="text-amber-400">*</span>` : ''}</span>`;
        })}</span>
                  </td>
                </tr>
                `}
              `)}
            </tbody>
          </table>
        </div>
      `;
  })}
  </div>
</div>
  `;
}

/* ─── Runner Page ─── */
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

function RunnerPage({ action, params, auth, setAction, setParams, setAuth, onToEval }) {
  const [result, setResult] = useState(null);
  const [loading, setLoading] = useState(false);

  async function run() {
    setLoading(true);
    let p = {}, a = null;
    try { p = JSON.parse(params); } catch (e) { setResult({ error: 'Invalid params JSON' }); setLoading(false); return; }
    if (auth.trim()) { try { a = JSON.parse(auth); } catch (e) { setResult({ error: 'Invalid auth JSON' }); setLoading(false); return; } }
    const r = await api('/api/action', { body: { action, params: p, auth: a } });
    setResult(r);
    setLoading(false);
  }

  const ic = 'w-full px-3 py-2 bg-gray-950 border border-gray-800 text-sm text-gray-200';

  return html`
  <div class="h-full flex flex-col">
  <${SectionHeader} title="Run Action" />
  <div class="flex-1 overflow-y-auto">
    <div class="p-5 space-y-3">
      <div>
        <label class="block text-xs text-gray-500 mb-1">Action</label>
        <input class=${ic} value=${action} onInput=${e => setAction(e.target.value)} placeholder="task.create" />
      </div>
      <div>
        <label class="block text-xs text-gray-500 mb-1">Params (JSON)</label>
        <textarea class=${ic} rows="6" value=${params} onInput=${e => setParams(e.target.value)}></textarea>
      </div>
      <div>
        <label class="block text-xs text-gray-500 mb-1">Auth (JSON, optional)</label>
        <textarea class=${ic} rows="2" value=${auth} onInput=${e => setAuth(e.target.value)}
          placeholder='{"roles":["user"]}'></textarea>
      </div>
      <div class="flex gap-2">
        <button class="px-4 py-1.5 bg-violet-600 hover:bg-violet-700 text-white text-sm rounded cursor-pointer border-none transition-colors"
          onClick=${run} disabled=${loading}>
          ${loading ? html`<span class="spinner mr-1"></span>` : ''} Run
        </button>
        <button class="px-4 py-1.5 bg-gray-800 hover:bg-gray-700 text-gray-300 text-sm rounded cursor-pointer border-none transition-colors"
          onClick=${() => onToEval(action, params, auth)}>
          → To Eval
        </button>
      </div>
    </div>
    ${result != null && html`
      <div class="border-t border-gray-800">
        <div class="px-5 py-3 bg-gray-900/50">
          <span class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Result</span>
        </div>
        <pre class="text-xs text-gray-300 px-5 pb-5 overflow-auto whitespace-pre-wrap">${JSON.stringify(result, null, 2)}</pre>
      </div>
    `}
  </div>
</div>
  `;
}

/* ─── Tools Page ─── */
