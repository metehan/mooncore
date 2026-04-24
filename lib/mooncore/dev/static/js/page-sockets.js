function SocketsPage() {
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [expanded, setExpanded] = useState({});
  const [filterDir, setFilterDir] = useState('');
  const [filterUser, setFilterUser] = useState('');
  const [filterChannel, setFilterChannel] = useState('');
  const [filterLimit, setFilterLimit] = useState('100');
  const intervalRef = useRef(null);
  const lastIdRef = useRef(null);

  const buildQuery = () => {
    const p = new URLSearchParams();
    if (filterDir) p.set('direction', filterDir);
    if (filterUser) p.set('user', filterUser.trim());
    if (filterChannel) p.set('channel', filterChannel.trim());
    if (filterLimit) p.set('limit', filterLimit);
    return p.toString() ? '?' + p.toString() : '';
  };

  const fetchData = useCallback(async () => {
    try {
      const d = await api('/api/socket-logs' + buildQuery());
      if (d && d.logs) setLogs(d.logs);
    } catch (e) { }
    setLoading(false);
  }, [filterDir, filterUser, filterChannel, filterLimit]);

  useEffect(() => { fetchData(); }, [fetchData]);
  useEffect(() => {
    if (autoRefresh) { intervalRef.current = setInterval(fetchData, 2000); }
    return () => clearInterval(intervalRef.current);
  }, [autoRefresh, fetchData]);

  const dirLabel = { in: '↓ in', out: '↑ out', publish: '↗ pub' };
  const dirColor = { in: 'text-cyan-400 bg-cyan-500/10', out: 'text-emerald-400 bg-emerald-500/10', publish: 'text-violet-400 bg-violet-500/10' };

  function relTime(ts) {
    const diff = Math.floor((Date.now() - ts) / 1000);
    if (diff < 5) return 'just now';
    if (diff < 60) return diff + 's ago';
    if (diff < 3600) return Math.floor(diff / 60) + 'm ago';
    return Math.floor(diff / 3600) + 'h ago';
  }

  if (loading) return html`<div class="p-8"><span class="spinner"></span></div>`;

  return html`
  <div class="h-full flex flex-col">
    <div class="px-5 py-3 border-b border-gray-800 flex items-center gap-2 flex-wrap bg-gray-900/50">
      <span class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Socket Messages</span>
      <span class="text-xs bg-gray-800 text-gray-500 px-1.5 py-0.5 rounded-full">${logs.length}</span>
      <div class="flex-1" />
      <select class="text-xs bg-gray-800 text-gray-300 border border-gray-700 rounded px-2 py-1"
        value=${filterDir} onChange=${e => setFilterDir(e.target.value)}>
        <option value="">all directions</option>
        <option value="in">↓ in</option>
        <option value="out">↑ out</option>
        <option value="publish">↗ publish</option>
      </select>
      <input class="text-xs bg-gray-800 text-gray-300 border border-gray-700 rounded px-2 py-1 w-24"
        placeholder="user" value=${filterUser} onInput=${e => setFilterUser(e.target.value)} />
      <input class="text-xs bg-gray-800 text-gray-300 border border-gray-700 rounded px-2 py-1 w-32"
        placeholder="channel" value=${filterChannel} onInput=${e => setFilterChannel(e.target.value)} />
      <input class="text-xs bg-gray-800 text-gray-300 border border-gray-700 rounded px-2 py-1 w-16"
        placeholder="limit" type="number" min="1" max="1000" value=${filterLimit} onInput=${e => setFilterLimit(e.target.value)} />
      <button class="text-xs text-gray-600 hover:text-gray-400 bg-transparent border-none cursor-pointer"
        onClick=${() => setAutoRefresh(!autoRefresh)}>${autoRefresh ? '\u23F8' : '\u25B6'}</button>
      <button class="text-xs text-gray-600 hover:text-gray-400 bg-transparent border-none cursor-pointer"
        onClick=${fetchData}>Refresh</button>
    </div>
    <div class="flex-1 overflow-y-auto font-mono text-xs">
      ${logs.length === 0 && html`<div class="p-5 text-gray-600">No socket messages recorded.</div>`}
      ${logs.map(entry => {
    const d = entry.data || {};
    const dir = String(d.direction || '');
    const isOpen = !!expanded[entry.id];
    const payloadStr = JSON.stringify(d.payload, null, 2);
    return html`
          <div key=${entry.id} class="border-b border-gray-800/40 hover:bg-gray-800/20">
            <div class="log-expand px-4 py-2 flex items-center gap-2" onClick=${() => setExpanded(p => ({ ...p, [entry.id]: !p[entry.id] }))}>
              <span class=${'px-1.5 py-0.5 rounded text-xs font-semibold ' + (dirColor[dir] || 'text-gray-500 bg-gray-800')}>${dirLabel[dir] || dir}</span>
              ${d.user && html`<span class="text-cyan-400">${d.user}</span>`}
              ${!d.user && d.pid && html`<span class="text-gray-600">${d.pid}</span>`}
              ${(d.channels || []).map(ch => html`
                <span key=${ch} class="text-gray-600 bg-gray-800/60 px-1 rounded">${ch}</span>
              `)}
              <span class="flex-1 text-gray-600 truncate">${JSON.stringify(d.payload)}</span>
              <span class="text-gray-700 shrink-0">${relTime(entry.timestamp)}</span>
              <span class="text-gray-700 shrink-0">${isOpen ? '▾' : '▸'}</span>
            </div>
            ${isOpen && html`
              <div class="px-4 pb-3 pl-8">
                ${d.pid && html`<div class="text-gray-600 mb-1">pid: ${d.pid}</div>`}
                ${d.dkey && html`<div class="text-gray-600 mb-1">dkey: ${d.dkey}</div>`}
                <pre class="text-gray-400 bg-gray-900 rounded p-2 overflow-x-auto text-xs whitespace-pre-wrap break-all">${payloadStr}</pre>
              </div>
            `}
          </div>
        `;
  })}
    </div>
  </div>
  `;
}

/* ─── Console Page ─── */
