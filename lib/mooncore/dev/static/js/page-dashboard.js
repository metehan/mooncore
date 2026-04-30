function DashboardPage() {
  const [data, setData] = useState(null);
  const [history, setHistory] = useState({ mem: [], cpu: [], procs: [], reductions: [] });
  const [prevSnap, setPrevSnap] = useState(null);
  const [cpuPct, setCpuPct] = useState([]);
  const [cpuRatio, setCpuRatio] = useState(0);
  const [tab, setTab] = useState('overview'); // overview | processes | ets | apps | topology
  const intervalRef = useRef(null);
  const MAX_HIST = 30;

  const fetchData = useCallback(async () => {
    try {
      const d = await api('/api/dashboard');
      setData(d);

      // Calculate per-scheduler CPU % from wall time deltas
      if (d.schedulers && d.schedulers.length > 0) {
        setPrevSnap(prev => {
          if (prev && prev.scheds && prev.scheds.length === d.schedulers.length) {
            const pcts = d.schedulers.map((s, i) => {
              const da = s.active - prev.scheds[i].active;
              const dt = s.total - prev.scheds[i].total;
              return dt > 0 ? (da / dt) * 100 : 0;
            });
            setCpuPct(pcts);
          }
          // CPU runtime ratio delta (instant utilization)
          if (prev && prev.runtime != null) {
            const dr = d.vm.runtime_ms - prev.runtime;
            const dw = d.vm.uptime_ms - prev.uptime;
            const ratio = dw > 0 ? (dr / dw) * 100 : 0;
            setCpuRatio(ratio);
            setHistory(h => ({
              ...h,
              cpu: [...h.cpu.slice(-(MAX_HIST - 1)), ratio]
            }));
          }
          return { scheds: d.schedulers, runtime: d.vm.runtime_ms, uptime: d.vm.uptime_ms };
        });
      }

      // Update history
      setHistory(h => ({
        ...h,
        mem: [...h.mem.slice(-(MAX_HIST - 1)), d.memory.total],
        procs: [...h.procs.slice(-(MAX_HIST - 1)), d.vm.process_count],
        reductions: [...h.reductions.slice(-(MAX_HIST - 1)), d.vm.reductions]
      }));
    } catch (e) { }
  }, []);

  useEffect(() => {
    fetchData();
    intervalRef.current = setInterval(fetchData, 2000);
    return () => clearInterval(intervalRef.current);
  }, [fetchData]);

  if (!data) return html`<div class="flex-1 flex flex-col">
    <div class="px-5 py-3 border-b border-gray-800 flex items-center gap-3 bg-gray-900/50">
      <span class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Dashboard</span>
    </div>
    <div class="p-5 space-y-6 animate-pulse">
      <div class="grid grid-cols-4 gap-4">
        ${[1, 2, 3, 4].map(() => html`
          <div class="bg-gray-900 border border-gray-800 rounded-lg p-4 h-24">
            <div class="h-2 w-16 bg-gray-800 rounded mb-3"></div>
            <div class="h-5 w-20 bg-gray-800 rounded"></div>
          </div>
        `)}
      </div>
      <div class="grid grid-cols-2 gap-6">
        <div class="bg-gray-900 border border-gray-800 rounded-lg p-4 h-40">
          <div class="h-2 w-24 bg-gray-800 rounded mb-4"></div>
          ${[1, 2, 3, 4, 5].map(() => html`<div class="h-2 bg-gray-800 rounded mb-2"></div>`)}
        </div>
        <div class="bg-gray-900 border border-gray-800 rounded-lg p-4 h-40">
          <div class="h-2 w-28 bg-gray-800 rounded mb-4"></div>
          <div class="grid grid-cols-4 gap-2">
            ${[1, 2, 3, 4, 5, 6, 7, 8].map(() => html`<div class="h-8 bg-gray-800 rounded"></div>`)}
          </div>
        </div>
      </div>
      <div class="bg-gray-900 border border-gray-800 rounded-lg p-4 h-32">
        <div class="h-2 w-20 bg-gray-800 rounded mb-4"></div>
        <div class="grid grid-cols-2 gap-4">
          ${[1, 2, 3, 4].map(() => html`<div class="h-3 bg-gray-800 rounded"></div>`)}
        </div>
      </div>
    </div>
  </div>`;

  const { memory, vm, top_processes, applications, topology } = data;
  const avgCpu = cpuRatio;

  const tabs = [
    { id: 'overview', label: 'Overview' },
    { id: 'processes', label: 'Processes (' + (top_processes || []).length + ')' },
    { id: 'apps', label: 'Apps (' + (applications || []).length + ')' },
    { id: 'topology', label: 'Topology (' + ((topology && topology.root_count) || 0) + ')' },
  ];

  return html`
  <div class="h-full flex flex-col">
  <div class="px-5 py-3 border-b border-gray-800 flex items-center gap-3 bg-gray-900/50">
    <span class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Dashboard</span>
    <span class="text-xs text-gray-600">Elixir ${vm.elixir_version} / OTP ${vm.otp_release}</span>
    <span class="text-xs text-gray-600">${vm.system_architecture}</span>
    <span class="text-xs text-gray-600 ml-auto">uptime ${fmtUptime(vm.uptime_ms)}</span>
  </div>
  <div class="flex border-b border-gray-800 px-3 shrink-0">
    ${tabs.map(t => html`
      <button key=${t.id}
        class="px-3 py-2 text-xs border-none cursor-pointer transition-colors
          ${tab === t.id ? 'text-violet-400 bg-transparent' : 'text-gray-500 hover:text-gray-300 bg-transparent'}"
        style=${tab === t.id ? 'box-shadow: inset 0 -2px 0 #7c3aed' : ''}
        onClick=${() => setTab(t.id)}>${t.label}</button>
    `)}
  </div>
  <div class="flex-1 overflow-y-auto">
    ${tab === 'overview' && html`<${DashOverview} data=${data} history=${history} cpuPct=${cpuPct} avgCpu=${avgCpu} />`}
    ${tab === 'processes' && html`<${DashProcesses} procs=${top_processes} />`}
    ${tab === 'apps' && html`<${DashApps} apps=${applications} />`}
    ${tab === 'topology' && html`<${DashTopology} topology=${topology} />`}
  </div>
</div>
  `;
}

function DashOverview({ data, history, cpuPct, avgCpu }) {
  const { memory, vm } = data;
  const memColors = { processes: '#7c3aed', binary: '#06b6d4', ets: '#f59e0b', atom: '#10b981', code: '#f87171' };
  // Detect whether we're running on a local host or private IP and
  // choose a less alarming color when the dashboard is accessed locally.
  const hostname = (typeof window !== 'undefined' && window.location) ? (window.location.hostname || window.location.host || window.location.href) : '';
  const isLocalHost = (() => {
    if (!hostname) return false;
    // Exact matches
    if (/^(localhost|0\.0\.0\.0|127\.0\.0\.1|::1)$/.test(hostname)) return true;
    if (hostname.endsWith('.local')) return true;
    // Common private IPv4 ranges and link-local
    if (/^(10|127)\./.test(hostname)) return true;
    if (/^169\.254\./.test(hostname)) return true;
    if (/^192\.168\./.test(hostname)) return true;
    if (/^172\.(1[6-9]|2[0-9]|3[0-1])\./.test(hostname)) return true;
    // Fallback: check full URL for localhost or common private segments (catches ports, hostnames with domains)
    try {
      const href = window.location.href || '';
      if (/localhost|127\.0\.0\.1|192\.168\.|10\.|169\.254\.|172\.(1[6-9]|2[0-9]|3[0-1])/.test(href)) return true;
    } catch (e) { }
    return false;
  })();
  const warnIconClass = isLocalHost ? 'text-gray-400/70' : 'text-amber-500/70';
  const baseTextClass = isLocalHost ? 'text-gray-400' : 'text-amber-400';
  const headerClass = isLocalHost ? 'text-gray-200' : 'text-amber-300';
  const wrapperClass = isLocalHost ? 'rounded-lg p-4 border bg-gray-900 border-gray-800 ' + baseTextClass : 'rounded-lg p-4 border ' + baseTextClass;
  const wrapperStyle = isLocalHost ? null : 'background:#1c1408;border-color:#3b2e14';

  return html`
  <div class="p-5 space-y-6">
  <!--Top stat cards-->
  <div class="grid grid-cols-4 gap-4">
    <div class="bg-gray-900 border border-gray-800 rounded-lg p-4">
      <div class="flex items-center justify-between mb-2">
        <span class="text-xs text-gray-500">Total Memory</span>
        <${Sparkline} data=${history.mem} color="#7c3aed" />
      </div>
      <div class="text-xl font-bold text-gray-200">${fmtBytes(memory.total)}</div>
    </div>
    <div class="bg-gray-900 border border-gray-800 rounded-lg p-4">
      <div class="flex items-center justify-between mb-2">
        <span class="text-xs text-gray-500">CPU Runtime</span>
        <${Sparkline} data=${history.cpu} color="#06b6d4" />
      </div>
      <div class="text-xl font-bold text-gray-200">${avgCpu.toFixed(1)}<span class="text-sm text-gray-500">%</span></div>
    </div>
    <div class="bg-gray-900 border border-gray-800 rounded-lg p-4">
      <div class="flex items-center justify-between mb-2">
        <span class="text-xs text-gray-500">Processes</span>
        <${Sparkline} data=${history.procs} color="#10b981" />
      </div>
      <div class="text-xl font-bold text-gray-200">${fmtNum(vm.process_count)}</div>
    </div>
    <div class="bg-gray-900 border border-gray-800 rounded-lg p-4">
      <div class="flex items-center justify-between mb-2">
        <span class="text-xs text-gray-500">Reductions</span>
        <${Sparkline} data=${history.reductions} color="#f59e0b" />
      </div>
      <div class="text-xl font-bold text-gray-200">${fmtNum(vm.reductions)}</div>
    </div>
  </div>

  <div class="grid grid-cols-2 gap-6">
    <!-- Memory breakdown -->
    <div class="bg-gray-900 border border-gray-800 rounded-lg p-4">
      <div class="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-3">Memory Breakdown</div>
      <${MemBar} label="Processes" bytes=${memory.processes} total=${memory.total} color=${memColors.processes} />
      <${MemBar} label="Binary" bytes=${memory.binary} total=${memory.total} color=${memColors.binary} />
      <${MemBar} label="ETS" bytes=${memory.ets} total=${memory.total} color=${memColors.ets} />
      <${MemBar} label="Atom" bytes=${memory.atom} total=${memory.total} color=${memColors.atom} />
      <${MemBar} label="Code" bytes=${memory.code} total=${memory.total} color=${memColors.code} />
    </div>

    <!-- Scheduler utilization -->
    <div class="bg-gray-900 border border-gray-800 rounded-lg p-4">
      <div class="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-3">
        Schedulers <span class="text-gray-600">(${vm.schedulers} online / ${vm.logical_processors} cores)</span>
      </div>
      ${cpuPct.length > 0 ? html`
        <div class="grid gap-1.5" style="grid-template-columns: repeat(auto-fill, minmax(52px, 1fr))">
          ${cpuPct.map((pct, i) => {
    const bg = pct > 80 ? '#f87171' : pct > 50 ? '#fbbf24' : '#06b6d4';
    const textC = pct > 80 ? 'text-red-400' : pct > 50 ? 'text-amber-400' : 'text-gray-400';
    return html`
            <div key=${i} class="bg-gray-800 rounded p-1.5 text-center relative overflow-hidden" title="Scheduler ${i + 1}: ${pct.toFixed(1)}%">
              <div class="absolute bottom-0 left-0 right-0 transition-all duration-700 rounded-b" style="height:${Math.max(pct, 1)}%;background:${bg};opacity:0.25"></div>
              <div class="relative text-xs font-mono ${textC}" style="font-size:10px">${pct.toFixed(0)}<span class="text-gray-600">%</span></div>
              <div class="relative text-gray-600" style="font-size:8px">${i + 1}</div>
            </div>`;
  })}
        </div>
      ` : html`<div class="text-xs text-gray-600">Collecting scheduler data...</div>`}
    </div>
  </div>

  <!--VM Limits-->
  <div class="bg-gray-900 border border-gray-800 rounded-lg p-4">
    <div class="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-3">VM Limits</div>
    <div class="grid grid-cols-2 gap-x-6 gap-y-2">
      <${Gauge} label="Processes" value=${vm.process_count} max=${vm.process_limit} color="#7c3aed" />
      <${Gauge} label="Atoms" value=${vm.atom_count} max=${vm.atom_limit} color="#10b981" />
      <${Gauge} label="Ports" value=${vm.port_count} max=${vm.port_limit} color="#06b6d4" />
      <${Gauge} label="ETS Tables" value=${vm.ets_count} max=${vm.ets_limit} color="#f59e0b" />
    </div>
  </div>

  <!--Quick stats row-->
  <div class="grid grid-cols-3 gap-4">
    <div class="bg-gray-900 border border-gray-800 rounded-lg p-3">
      <span class="text-xs text-gray-500">Runtime</span>
      <div class="text-sm font-mono text-gray-300 mt-1">${fmtUptime(vm.runtime_ms)}</div>
    </div>
    <div class="bg-gray-900 border border-gray-800 rounded-lg p-3">
      <span class="text-xs text-gray-500">CPU Runtime Ratio</span>
      <div class="text-sm font-mono text-gray-300 mt-1">${vm.uptime_ms > 0 ? (vm.runtime_ms / vm.uptime_ms * 100).toFixed(2) : 0}%</div>
    </div>
    <div class="bg-gray-900 border border-gray-800 rounded-lg p-3">
      <span class="text-xs text-gray-500">ETS Tables</span>
      <div class="text-sm font-mono text-gray-300 mt-1">${vm.ets_count} <span class="text-gray-600">/ ${fmtBytes(memory.ets)}</span></div>
    </div>
  </div>

  <!-- Devtools warning -->
  <div class="${wrapperClass}" style=${wrapperStyle}>
    <div class="flex items-start gap-3">
      <span class="${warnIconClass} text-lg leading-none mt-0.5">⚠</span>
      <div class="space-y-1.5">
        <div class="text-sm font-semibold ${headerClass}">Do not expose developer tools to the internet</div>
        <div class="text-xs leading-relaxed">
          These developer tools are intended for local development only and are not a secure observability or administration interface.
          <p class="mt-1.5">Tokens, the interactive login password, and the development secret (MOONCORE_DEV_SECRET) are <strong>functionally equivalent</strong>: tokens are issued for OAuth-style development compatibility and are not intended to grant reduced or scoped privileges. The devtools include an <code>eval</code> capability that can read environment variables and execute arbitrary OS commands; therefore, <strong>anyone with a token or the dev secret can effectively obtain shell-level access</strong> and retrieve secrets. Do not expose these developer tools or their tokens to untrusted networks or the public internet.</p>
        </div>
      </div>
    </div>
  </div>
</div>
  `;
}

function DashProcesses({ procs }) {
  return html`
  <div>
  <table>
    <thead>
      <tr class="border-b border-gray-800 bg-gray-900/50">
        <th class="px-4 py-2 text-xs text-gray-500 font-medium">Name / PID</th>
        <th class="px-4 py-2 text-xs text-gray-500 font-medium text-right">Memory</th>
        <th class="px-4 py-2 text-xs text-gray-500 font-medium text-right">MQ</th>
        <th class="px-4 py-2 text-xs text-gray-500 font-medium text-right">Reductions</th>
        <th class="px-4 py-2 text-xs text-gray-500 font-medium">Status</th>
        <th class="px-4 py-2 text-xs text-gray-500 font-medium">Current Function</th>
      </tr>
    </thead>
    <tbody>
      ${(procs || []).map((p, i) => html`
        <tr key=${i} class="border-b border-gray-800/40 hover:bg-gray-800/30 transition-colors">
          <td class="px-4 py-2">
            <div class="text-xs font-mono ${p.name ? 'text-violet-400' : 'text-gray-500'}">${p.name || p.pid}</div>
            ${p.name && html`<div class="text-xs text-gray-600 font-mono">${p.pid}</div>`}
          </td>
          <td class="px-4 py-2 text-xs text-gray-300 text-right font-mono">${fmtBytes(p.memory)}</td>
          <td class="px-4 py-2 text-xs text-right font-mono ${p.mq_len > 0 ? (p.mq_len > 100 ? 'text-red-400' : 'text-amber-400') : 'text-gray-500'}">${p.mq_len}</td>
          <td class="px-4 py-2 text-xs text-gray-400 text-right font-mono">${fmtNum(p.reductions)}</td>
          <td class="px-4 py-2">
            <span class="text-xs px-1.5 py-0.5 rounded ${p.status === 'running' ? 'bg-emerald-500/15 text-emerald-400' : p.status === 'waiting' ? 'bg-gray-800 text-gray-500' : 'bg-amber-500/15 text-amber-400'}">${p.status}</span>
          </td>
          <td class="px-4 py-2 text-xs text-gray-500 font-mono truncate max-w-xs">${p.current_fn || '-'}</td>
        </tr>
      `)}
    </tbody>
  </table>
</div>
  `;
}

function DashApps({ apps }) {
  return html`
  <div>
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

