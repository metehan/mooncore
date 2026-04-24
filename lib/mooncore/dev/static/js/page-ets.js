function EtsPage() {
  const [tables, setTables] = useState(null);
  const [error, setError] = useState(null);
  const intervalRef = useRef(null);

  const fetchTables = useCallback(async () => {
    try {
      const d = await api('/api/dashboard');
      setTables(d.ets_tables || []);
    } catch (e) { setError(String(e)); }
  }, []);

  useEffect(() => {
    fetchTables();
    intervalRef.current = setInterval(fetchTables, 5000);
    return () => clearInterval(intervalRef.current);
  }, [fetchTables]);

  if (error) return html`<div class="p-6 text-sm text-red-400">${error}</div>`;
  if (!tables) return html`<div class="flex-1 flex items-center justify-center text-sm text-gray-600">Loading...</div>`;

  return html`<${EtsTableBrowser} tables=${tables} />`;
}

function EtsTableBrowser({ tables }) {
  const allTables = tables || [];
  const totalMem = allTables.reduce((s, t) => s + t.memory, 0);
  const totalRows = allTables.reduce((s, t) => s + t.size, 0);
  const [tableQuery, setTableQuery] = useState('');
  const [showEmpty, setShowEmpty] = useState(false);
  const [selectedId, setSelectedId] = useState(null);
  const [rowFilter, setRowFilter] = useState('');
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState([]);
  const [meta, setMeta] = useState({ total_matching: 0, total_pages: 1, has_prev: false, has_next: false });
  const [loadingRows, setLoadingRows] = useState(false);
  const [rowError, setRowError] = useState(null);
  const [showInsert, setShowInsert] = useState(false);
  const [insertTerm, setInsertTerm] = useState('');
  const [insertError, setInsertError] = useState(null);
  const [insertLoading, setInsertLoading] = useState(false);

  const emptyCount = useMemo(() => allTables.filter(t => t.size === 0).length, [allTables]);

  const filteredTables = useMemo(() => {
    const query = tableQuery.trim().toLowerCase();
    let list = showEmpty ? allTables : allTables.filter(t => t.size > 0);
    if (!query) return list;
    return list.filter(t => `${t.name} ${t.type} ${t.protection}`.toLowerCase().includes(query));
  }, [allTables, tableQuery, showEmpty]);

  const selectedTable = useMemo(() => {
    return filteredTables.find(t => t.id === selectedId) || filteredTables[0] || null;
  }, [filteredTables, selectedId]);

  useEffect(() => {
    if (selectedTable && selectedId !== selectedTable.id) setSelectedId(selectedTable.id);
    if (!selectedTable && selectedId !== null) setSelectedId(null);
  }, [selectedTable, selectedId]);

  useEffect(() => { setPage(1); }, [selectedId, rowFilter]);

  useEffect(() => {
    let cancelled = false;
    async function loadRows() {
      if (!selectedTable) { setRows([]); setRowError(null); setMeta({ total_matching: 0, total_pages: 1, has_prev: false, has_next: false }); return; }
      setLoadingRows(true); setRowError(null);
      try {
        const d = await api(`/api/ets/rows?table=${encodeURIComponent(selectedTable.id)}&filter=${encodeURIComponent(rowFilter)}&page=${page}&limit=50`);
        if (cancelled) return;
        if (d.ok) { setRows(d.rows || []); setMeta({ total_matching: d.total_matching || 0, total_pages: d.total_pages || 1, has_prev: !!d.has_prev, has_next: !!d.has_next }); }
        else { setRows([]); setMeta({ total_matching: 0, total_pages: 1, has_prev: false, has_next: false }); setRowError(d.error || 'Could not load rows'); }
      } catch (e) { if (!cancelled) { setRows([]); setMeta({ total_matching: 0, total_pages: 1, has_prev: false, has_next: false }); setRowError(String(e)); } }
      if (!cancelled) setLoadingRows(false);
    }
    loadRows();
    return () => { cancelled = true; };
  }, [selectedTable ? selectedTable.id : null, rowFilter, page]);

  async function deleteRow(keyPreview) {
    if (!selectedTable) return;
    const d = await api('/api/ets/delete', { body: { table: selectedTable.id, key: keyPreview } });
    if (d.ok) setPage(p => p); // trigger reload
    else alert(d.error);
  }

  async function insertRow() {
    if (!selectedTable || !insertTerm.trim()) return;
    setInsertLoading(true); setInsertError(null);
    const d = await api('/api/ets/insert', { body: { table: selectedTable.id, term: insertTerm } });
    setInsertLoading(false);
    if (d.ok) { setInsertTerm(''); setShowInsert(false); setPage(1); }
    else setInsertError(d.error);
  }

  return html`
  <div class="h-full flex min-h-0">
    <div class="w-72 border-r border-gray-800 bg-gray-900/50 shrink-0 flex flex-col">
      <${SectionHeader} title="ETS Tables" count=${filteredTables.length} />
      <div class="px-4 py-3 border-b border-gray-800 bg-gray-950/40 space-y-3">
        <div class="grid grid-cols-2 gap-2 text-xs">
          <div class="rounded-lg border border-gray-800 bg-gray-900 px-3 py-2">
            <div class="text-gray-500">Memory</div>
            <div class="text-gray-200 font-mono mt-1">${fmtBytes(totalMem)}</div>
          </div>
          <div class="rounded-lg border border-gray-800 bg-gray-900 px-3 py-2">
            <div class="text-gray-500">Rows</div>
            <div class="text-gray-200 font-mono mt-1">${fmtNum(totalRows)}</div>
          </div>
        </div>
        <input value=${tableQuery} onInput=${e => setTableQuery(e.target.value)} placeholder="Filter tables"
          class="w-full bg-gray-950 border border-gray-800 rounded-lg px-3 py-2 text-sm text-gray-200" />
      </div>
      <div class="flex-1 overflow-y-auto">
        ${filteredTables.length === 0
      ? html`<div class="p-5 text-sm text-gray-600">No ETS tables match the current filter.</div>`
      : filteredTables.map(t => html`
            <button key=${t.id}
              class="group w-full text-left px-4 py-3 bg-transparent border-x-0 border-t-0 border-b border-gray-800/30 cursor-pointer transition-colors ${selectedTable && selectedTable.id === t.id ? 'bg-violet-500/10' : 'hover:bg-gray-800/40'}"
              onClick=${() => setSelectedId(t.id)}>
              <div class="flex items-start justify-between gap-3">
                <div class="min-w-0">
                  <div class="text-xs font-mono ${selectedTable && selectedTable.id === t.id ? 'text-violet-300' : 'text-violet-400'} break-all">${t.name}</div>
                  <div class="mt-1 flex items-center gap-2 text-[11px] text-gray-500">
                    <span>${t.type}</span>
                    <span>${fmtNum(t.size)} rows</span>
                  </div>
                </div>
                <span class="text-[10px] px-1.5 py-0.5 rounded-full ${t.protection === 'public' ? 'bg-emerald-500/10 text-emerald-300' : t.protection === 'protected' ? 'bg-cyan-500/10 text-cyan-300' : 'bg-amber-500/10 text-amber-300'}">${t.protection}</span>
              </div>
            </button>
          `)
    }
        ${!showEmpty && emptyCount > 0 && html`
          <div class="px-4 py-3 text-[11px] text-gray-600">
            ${emptyCount} table${emptyCount === 1 ? '' : 's'} with no records hidden.${' '}
            <button class="text-gray-500 underline bg-transparent border-none cursor-pointer p-0" onClick=${() => setShowEmpty(true)}>Show all tables</button>
          </div>
        `}
      </div>
    </div>

    <div class="flex-1 min-w-0 flex flex-col bg-gray-950/30">
      ${selectedTable ? html`
        <div class="px-5 py-3 border-b border-gray-800 bg-gray-950/40 shrink-0 space-y-3">
          <div class="flex items-center justify-between gap-4">
            <div class="flex items-center gap-3 min-w-0">
              <div class="text-sm font-mono text-violet-300 break-all">${selectedTable.name}</div>
              <span class="text-[10px] px-2 py-0.5 rounded-full bg-gray-900 border border-gray-800 text-gray-400">${selectedTable.type}</span>
              <span class="text-[10px] px-2 py-0.5 rounded-full ${selectedTable.protection === 'public' ? 'bg-emerald-500/10 text-emerald-300 border border-emerald-500/20' : selectedTable.protection === 'protected' ? 'bg-cyan-500/10 text-cyan-300 border border-cyan-500/20' : 'bg-amber-500/10 text-amber-300 border border-amber-500/20'}">${selectedTable.protection}</span>
            </div>
            <div class="flex items-center gap-2 shrink-0 text-xs text-gray-500">
              <span>${fmtNum(selectedTable.size)} rows</span>
              <span>${fmtBytes(selectedTable.memory)}</span>
              ${selectedTable.protection !== 'private' && html`
                <button class="px-2.5 py-1.5 text-xs rounded-lg border border-violet-500/30 bg-violet-500/10 text-violet-300 cursor-pointer"
                  onClick=${() => { setShowInsert(v => !v); setInsertError(null); }}>+ Insert</button>
              `}
            </div>
          </div>
          ${showInsert && html`
            <div class="space-y-2">
              <textarea value=${insertTerm} onInput=${e => setInsertTerm(e.target.value)} rows="3"
                placeholder='Elixir term, e.g. {:my_key, "hello", 42}'
                class="w-full bg-gray-950 border border-gray-800 rounded-lg px-3 py-2 text-sm font-mono text-gray-200 resize-none" />
              ${insertError && html`<div class="text-xs text-red-400">${insertError}</div>`}
              <div class="flex gap-2">
                <button class="px-3 py-1.5 text-xs rounded-lg border border-emerald-500/30 bg-emerald-500/10 text-emerald-300 cursor-pointer disabled:opacity-40" onClick=${insertRow} disabled=${insertLoading}>${insertLoading ? 'Inserting…' : 'Insert'}</button>
                <button class="px-3 py-1.5 text-xs rounded-lg border border-gray-800 bg-gray-900 text-gray-400 cursor-pointer" onClick=${() => { setShowInsert(false); setInsertError(null); setInsertTerm(''); }}>Cancel</button>
              </div>
            </div>
          `}
          <div class="flex items-center gap-3">
            <input value=${rowFilter} onInput=${e => setRowFilter(e.target.value)} placeholder="Filter rows"
              class="flex-1 bg-gray-950 border border-gray-800 rounded-lg px-3 py-2 text-sm text-gray-200" />
            <button class="px-3 py-1.5 text-xs rounded-lg border border-gray-800 bg-gray-900 text-gray-300 disabled:opacity-40" onClick=${() => setPage(p => Math.max(1, p - 1))} disabled=${!meta.has_prev || loadingRows}>Prev</button>
            <div class="text-xs text-gray-500 whitespace-nowrap">${page} / ${meta.total_pages || 1}</div>
            <button class="px-3 py-1.5 text-xs rounded-lg border border-gray-800 bg-gray-900 text-gray-300 disabled:opacity-40" onClick=${() => setPage(p => p + 1)} disabled=${!meta.has_next || loadingRows}>Next</button>
          </div>
        </div>
        <div class="flex-1 overflow-y-auto px-5 py-4">
          ${loadingRows
        ? html`<div class="text-sm text-gray-500">Loading…</div>`
        : rowError
          ? html`<div class="rounded-lg border border-red-500/20 bg-red-500/5 px-4 py-3 text-sm text-red-300">${rowError}</div>`
          : rows.length === 0
            ? html`<div class="text-sm text-gray-500">No rows match.</div>`
            : html`<div class="space-y-1">${rows.map(row => html`<${EtsRowCard} key=${row.index} row=${row} tableId=${selectedTable.id} protection=${selectedTable.protection} onDelete=${deleteRow} onReload=${() => setPage(p => p)} />`)}</div>`}
        </div>
      ` : html`<div class="flex-1 flex items-center justify-center text-sm text-gray-600">Select an ETS table to inspect it.</div>`}
    </div>
  </div>
  `;
}

function EtsRowCard({ row, tableId, protection, onDelete, onReload }) {
  const [open, setOpen] = useState(false);
  const [deleting, setDeleting] = useState(false);

  // Extract key term string (first element of outermost tuple, or full row for non-tuple)
  function keyTerm() {
    if (row.term && row.term.kind === 'tuple' && row.term.items && row.term.items.length > 0) {
      const keyNode = row.term.items[0];
      if (keyNode.kind === 'atom' || keyNode.kind === 'inspect') return keyNode.value;
      if (keyNode.kind === 'scalar') return String(keyNode.value);
      if (keyNode.kind === 'binary') return JSON.stringify(keyNode.value);
    }
    return row.preview.split('\n')[0];
  }

  async function handleDelete() {
    if (!confirm('Delete this row?')) return;
    setDeleting(true);
    await onDelete(keyTerm());
    setDeleting(false);
    onReload();
  }

  return html`
  <div class="rounded-lg border border-gray-800/60 bg-gray-900/60 overflow-hidden">
    <div class="flex items-center gap-2 px-3 py-2 cursor-pointer select-none hover:bg-gray-800/30 transition-colors"
      onClick=${() => setOpen(v => !v)}>
      <span class="text-gray-600 text-[10px] shrink-0">${open ? '▾' : '▸'}</span>
      <pre class="flex-1 min-w-0 text-xs font-mono text-gray-300 whitespace-nowrap overflow-hidden text-ellipsis">${row.preview.split('\n')[0]}</pre>
      <span class="text-[10px] font-mono text-gray-600 shrink-0">${fmtBytes(row.bytes)}</span>
      ${protection === 'public' && html`
        <button class="text-[10px] px-1.5 py-0.5 rounded border border-red-500/20 bg-red-500/5 text-red-400 cursor-pointer disabled:opacity-40 shrink-0"
          onClick=${e => { e.stopPropagation(); handleDelete(); }} disabled=${deleting}>
          ${deleting ? '…' : '✕'}
        </button>
      `}
    </div>
    ${open && html`
      <div class="px-4 pb-4 pt-2 border-t border-gray-800/60 bg-gray-950/40">
        <${EtsTermNode} term=${row.term} depth=${0} />
      </div>
    `}
  </div>
  `;
}

function EtsTermNode({ term, depth }) {
  if (!term) return html`<span class="text-xs text-gray-600">null</span>`;

  if (term.kind === 'scalar') {
    return html`<span class="text-sm font-mono text-gray-200">${String(term.value)}</span>`;
  }

  if (term.kind === 'atom') {
    return html`<span class="inline-flex px-2 py-1 rounded-md bg-violet-500/10 text-violet-300 text-xs font-mono">${term.value}</span>`;
  }

  if (term.kind === 'binary') {
    return html`
    <div class="space-y-2">
      <div class="text-xs text-cyan-300 font-mono">binary <span class="text-gray-500">(${fmtNum(term.length || 0)} bytes)</span></div>
      <pre class="text-xs text-gray-300 whitespace-pre-wrap break-all bg-gray-950 border border-gray-800 rounded-lg p-3">${term.value}</pre>
    </div>`;
  }

  if (term.kind === 'inspect') {
    return html`<pre class="text-xs text-gray-300 whitespace-pre-wrap break-all bg-gray-950 border border-gray-800 rounded-lg p-3">${term.value}</pre>`;
  }

  if (term.kind === 'tuple' || term.kind === 'list') {
    const label = term.kind === 'tuple' ? 'Tuple' : 'List';
    const items = term.items || [];
    return html`
    <details open=${depth < 1} class="rounded-lg border border-gray-800 bg-gray-950/30">
      <summary class="px-3 py-2 cursor-pointer text-xs text-gray-400 select-none">${label} <span class="text-gray-600">(${term.size})</span></summary>
      <div class="px-3 pb-3 space-y-2">
        ${items.map((item, index) => html`
          <div key=${index} class="flex items-start gap-3 border-l border-gray-800 pl-3">
            <div class="text-[11px] font-mono text-gray-600 pt-1 shrink-0">${index}</div>
            <div class="min-w-0 flex-1"><${EtsTermNode} term=${item} depth=${depth + 1} /></div>
          </div>
        `)}
        ${term.truncated && html`<div class="text-xs text-gray-600">Truncated after 25 items.</div>`}
      </div>
    </details>`;
  }

  if (term.kind === 'map') {
    const entries = term.entries || [];
    return html`
    <details open=${depth < 1} class="rounded-lg border border-gray-800 bg-gray-950/30">
      <summary class="px-3 py-2 cursor-pointer text-xs text-gray-400 select-none">Map <span class="text-gray-600">(${term.size})</span></summary>
      <div class="px-3 pb-3 space-y-3">
        ${entries.map((entry, index) => html`
          <div key=${index} class="rounded-lg border border-gray-800 bg-gray-950/40 overflow-hidden">
            <div class="px-3 py-2 border-b border-gray-800 text-[11px] uppercase tracking-wider text-gray-500">Entry ${index + 1}</div>
            <div class="grid grid-cols-2 gap-0">
              <div class="p-3 border-r border-gray-800 min-w-0">
                <div class="text-[11px] uppercase tracking-wider text-gray-600 mb-2">Key</div>
                <${EtsTermNode} term=${entry.key} depth=${depth + 1} />
              </div>
              <div class="p-3 min-w-0">
                <div class="text-[11px] uppercase tracking-wider text-gray-600 mb-2">Value</div>
                <${EtsTermNode} term=${entry.value} depth=${depth + 1} />
              </div>
            </div>
          </div>
        `)}
        ${term.truncated && html`<div class="text-xs text-gray-600">Truncated after 25 entries.</div>`}
      </div>
    </details>`;
  }

  return html`<pre class="text-xs text-gray-300 whitespace-pre-wrap break-all bg-gray-950 border border-gray-800 rounded-lg p-3">${JSON.stringify(term, null, 2)}</pre>`;
}

