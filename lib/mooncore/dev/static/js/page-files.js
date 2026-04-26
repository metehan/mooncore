function FilesPage({ onOpenFile }) {
  const [cwd, setCwd] = useState('.');
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async (path) => {
    setLoading(true);
    const d = await api('/api/files?path=' + encodeURIComponent(path));
    setItems(d.items || []);
    setCwd(d.path || path);
    setLoading(false);
  }, []);

  useEffect(() => { load('.'); }, []);

  async function openFile(path) {
    const d = await api('/api/file?path=' + encodeURIComponent(path));
    if (d.content != null) {
      onOpenFile({ path: d.path, content: d.content });
    }
  }

  function goUp() {
    if (cwd === '.' || cwd === '') return;
    const parent = cwd.split('/').slice(0, -1).join('/') || '.';
    load(parent);
  }

  return html`
  <div class="h-full flex flex-col">
  <div class="px-5 py-3 border-b border-gray-800 flex items-center gap-3 bg-gray-900/50">
    <span class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Files</span>
    <code class="text-xs text-gray-500 flex-1">${cwd === '.' ? '/' : '/' + cwd}</code>
    ${cwd !== '.' && html`
      <button class="text-xs text-gray-500 hover:text-gray-300 bg-transparent border-none cursor-pointer" onClick=${goUp}>\u2191 Up</button>
    `}
  </div>
  <div class="flex-1 overflow-y-auto">
  ${loading ? html`<div class="p-4"><span class="spinner"></span></div>` : html`
    <div>
      ${items.map(i => html`
        <div class="flex items-center gap-2.5 px-5 py-1.5 hover:bg-gray-800/40 cursor-pointer transition-colors border-b border-gray-800/30"
          onClick=${() => i.type === 'dir' ? load(i.path) : openFile(i.path)}>
          <span class="w-4 text-center text-xs">${i.type === 'dir' ? '\uD83D\uDCC1' : '\uD83D\uDCC4'}</span>
          <span class="text-sm flex-1 ${i.type === 'dir' ? 'text-violet-400' : 'text-gray-300'}">${i.name}</span>
          ${i.size != null && html`<span class="text-xs text-gray-600">${formatSize(i.size)}</span>`}
        </div>
      `)}
      ${items.length === 0 && html`<div class="p-4 text-gray-600 text-sm">Empty directory</div>`}
    </div>
  `}
  </div>
</div>
  `;
}

function formatSize(bytes) {
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
  return (bytes / 1024 / 1024).toFixed(1) + ' MB';
}

/* ─── Config Page ─── */
/* ─── Right Panel: Action Call Logs ─── */
function ActionLogsPanel({ onReplay }) {
  const [logs, setLogs] = useState([]);
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [filter, setFilter] = useState('');
  const intervalRef = useRef(null);

  const fetchLogs = useCallback(async () => {
    try {
      const d = await api('/api/logs?tag=action');
      setLogs(d.logs || []);
    } catch (e) { }
  }, []);

  useEffect(() => { fetchLogs(); }, []);

  useEffect(() => {
    if (autoRefresh) { intervalRef.current = setInterval(fetchLogs, 2000); }
    return () => clearInterval(intervalRef.current);
  }, [autoRefresh, fetchLogs]);

  async function clearLogs() {
    await api('/api/mcp', { body: { tool: 'clear_logs' } });
    setLogs([]);
  }

  const filtered = useMemo(() => {
    if (!filter.trim()) return logs;
    const q = filter.toLowerCase();
    return logs.filter(l => {
      const d = l.data || {};
      return (d.action || '').toLowerCase().includes(q) || (d.source || '').toLowerCase().includes(q);
    });
  }, [logs, filter]);

  return html`
  <div class="flex flex-col h-full">
  <div class="px-3 py-2 border-b border-gray-800 flex items-center gap-2 shrink-0">
    <span class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Action Logs</span>
    <span class="text-xs bg-gray-800 text-gray-500 px-1.5 py-0.5 rounded-full">${filtered.length}</span>
    <div class="flex-1" />
    <button class="text-xs text-gray-600 hover:text-gray-400 bg-transparent border-none cursor-pointer"
      onClick=${() => setAutoRefresh(!autoRefresh)}>${autoRefresh ? '\u23F8' : '\u25B6'}</button>
    <button class="text-xs text-gray-600 hover:text-gray-400 bg-transparent border-none cursor-pointer" onClick=${clearLogs}>Clear</button>
  </div>
  <div class="px-3 py-1.5 border-b border-gray-800 shrink-0">
    <input class="w-full px-2 py-1 bg-gray-950 border border-gray-800 text-xs text-gray-300"
      placeholder="Filter by action or source..." value=${filter} onInput=${e => setFilter(e.target.value)} />
  </div>
  <div class="flex-1 overflow-y-auto">
    ${filtered.length === 0
      ? html`<div class="p-4 text-xs text-gray-600">No action calls logged yet.</div>`
      : filtered.map(l => {
        const data = l.data || {};
        const hasError = data.response && (data.response.error || data.response.errors);
        const sourceTone = data.source === 'ws' ? 'text-cyan-400' : data.source === 'mcp' ? 'text-emerald-400' : data.source === 'elixir' ? 'text-amber-400' : 'text-gray-600';
        return html`
          <div key=${l.id} class="group border-b border-gray-800/40 log-new cursor-pointer"
            onClick=${() => onReplay(data)}>
            <div class="px-3 py-2 flex items-center gap-2">
              <span class="text-xs font-mono text-violet-400 flex-1 truncate">${data.action || '?'}</span>
              <span class="text-xs px-1 ${sourceTone}">${data.source || ''}</span>
              ${hasError && html`<span class="text-xs text-red-400">\u2717</span>`}
              <span class="text-xs text-gray-600">${data.duration}ms</span>
            </div>
          </div>
        `;
      })
    }
  </div>
}
</div>
  `;
}
