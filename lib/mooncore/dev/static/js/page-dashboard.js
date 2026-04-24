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
</div>
  `;
}

function DashProcesses({ procs }) {
  return html`
  <div >
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

