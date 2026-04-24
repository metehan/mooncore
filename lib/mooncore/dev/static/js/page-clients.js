function ClientsPage() {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [expanded, setExpanded] = useState({});
  const intervalRef = useRef(null);

  const fetchData = useCallback(async () => {
    try {
      const d = await api('/api/clients');
      setData(d);
    } catch (e) { }
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, []);
  useEffect(() => {
    if (autoRefresh) { intervalRef.current = setInterval(fetchData, 3000); }
    return () => clearInterval(intervalRef.current);
  }, [autoRefresh, fetchData]);

  function toggleGroup(group) {
    setExpanded(prev => ({ ...prev, [group]: !prev[group] }));
  }

  if (loading) return html`<div class="p-8"> <span class="spinner"></span></div> `;

  const groups = (data && data.groups) || [];
  const totalClients = groups.reduce((s, g) => s + g.total, 0);
  const totalChannels = groups.reduce((s, g) => s + g.channels.length, 0);

  return html`
  <div class="h-full flex flex-col">
  <div class="px-5 py-3 border-b border-gray-800 flex items-center justify-between bg-gray-900/50">
    <div class="flex items-center gap-2">
      <span class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Connected Clients</span>
      <span class="text-xs bg-gray-800 text-gray-500 px-1.5 py-0.5 rounded-full">${totalClients} connections</span>
      <span class="text-xs bg-gray-800 text-gray-500 px-1.5 py-0.5 rounded-full">${totalChannels} channels</span>
    </div>
    <div class="flex items-center gap-2">
      <button class="text-xs text-gray-600 hover:text-gray-400 bg-transparent border-none cursor-pointer"
        onClick=${() => setAutoRefresh(!autoRefresh)}>
        ${autoRefresh ? '\u23F8' : '\u25B6'}
      </button>
      <button class="text-xs text-gray-600 hover:text-gray-400 bg-transparent border-none cursor-pointer"
        onClick=${fetchData}>Refresh</button>
    </div>
  </div>
  <div class="flex-1 overflow-y-auto">
    ${data && data.error && html`
      <div class="px-5 py-3 text-xs text-amber-400">${data.error}</div>
    `}
    ${groups.length === 0 && !data?.error && html`
      <div class="p-5 text-sm text-gray-600">No connected clients.</div>
    `}
    ${groups.map(g => {
    const isOpen = expanded[`${g.group}:${g.pool}`] !== false; // default open
    return html`
        <div key=${`${g.group}:${g.pool}`} class="border-b border-gray-800">
          <div class="log-expand px-5 py-2.5 flex items-center gap-2 bg-gray-900/30 hover:bg-gray-800/30"
            onClick=${() => toggleGroup(`${g.group}:${g.pool}`)}>
            <span class="text-xs text-gray-600 w-3">${isOpen ? '\u25BE' : '\u25B8'}</span>
            <span class="text-sm font-semibold text-gray-300 flex-1">${g.group}</span>
            <span class="text-xs font-mono text-gray-600 bg-gray-800/60 px-1.5 py-0.5 rounded">${g.pool}</span>
            <span class="text-xs bg-violet-500/15 text-violet-400 px-1.5 py-0.5 rounded-full">${g.total} pid${g.total !== 1 ? 's' : ''}</span>
            <span class="text-xs bg-gray-800 text-gray-500 px-1.5 py-0.5 rounded-full">${g.channels.length} ch</span>
          </div>
          ${isOpen && html`
            <div>
              ${g.channels.map(ch => html`
                <${ChannelRow} key=${ch.channel} channel=${ch} />
              `)}
            </div>
          `}
        </div>
      `;
  })}
  </div>
</div>
  `;
}

function ChannelRow({ channel }) {
  const [showMembers, setShowMembers] = useState(false);
  const isUser = channel.channel.startsWith('@');
  const icon = isUser ? '@' : '#';
  const color = isUser ? 'text-cyan-400' : 'text-violet-400';

  return html`
  <div class="border-b border-gray-800/30">
    <div class="log-expand px-5 pl-10 py-2 flex items-center gap-2 hover:bg-gray-800/20"
      onClick=${() => setShowMembers(!showMembers)}>
      <span class="text-xs w-3 ${color} font-mono">${icon}</span>
      <span class="text-xs font-mono ${color} flex-1">${channel.channel}</span>
      <span class="text-xs text-gray-600">${channel.count}</span>
    </div>
    ${showMembers && html`
      <div class="pl-16 pr-5 pb-2 space-y-0.5">
        ${channel.members.map((pid, i) => html`
          <div key=${i} class="text-xs font-mono text-gray-500 py-0.5 flex items-center gap-2">
            <span class="w-1.5 h-1.5 rounded-full bg-emerald-400 shrink-0"></span>
            ${pid}
          </div>
        `)}
      </div>
    `}
  </div>
  `;
}

/* ─── Sockets Page ─── */
