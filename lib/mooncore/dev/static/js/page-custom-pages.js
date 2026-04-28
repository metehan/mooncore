/* ── Custom Pages page (old wrapper - deprecated, keeping for compatibility) ── */
function CustomPagesPage() {
  const [pages, setPages] = useState([]);
  const [selectedPage, setSelectedPage] = useState(null);
  const [pageData, setPageData] = useState(null);
  const [widgetData, setWidgetData] = useState({});
  const [loading, setLoading] = useState(true);
  const [evalModal, setEvalModal] = useState(null);

  useEffect(() => {
    async function fetchPages() {
      try {
        const res = await api('/api/devtools/pages');
        setPages(res.pages || []);
        if (res.pages && res.pages.length > 0 && !selectedPage) {
          setSelectedPage(res.pages[0].name);
        }
      } catch (e) {
        setPages([]);
      } finally {
        setLoading(false);
      }
    }
    fetchPages();
  }, []);

  useEffect(() => {
    if (!selectedPage) return;
    async function fetchPageData() {
      try {
        const res = await api('/api/devtools/page', { params: { name: selectedPage } });
        setPageData(res);
      } catch (e) {
        setPageData(null);
      }
    }
    fetchPageData();
  }, [selectedPage]);

  useEffect(() => {
    if (!pageData || !pageData.widgets) return;
    async function fetchWidgetData() {
      const results = {};
      for (const w of pageData.widgets) {
        if (!w.source) continue;
        const type = w.source.type;
        const key = w.source.key;
        try {
          const res = await api('/api/devtools/data', { params: { type, key } });
          results[w.id] = res.data;
        } catch (e) {
          results[w.id] = null;
        }
      }
      setWidgetData(results);
    }
    fetchWidgetData();
  }, [pageData]);

  if (loading) {
    return html`<div class="flex-1 flex flex-col">
      <${SectionHeader} title="Custom Pages" />
      <div class="p-5 text-gray-500 text-sm">Loading...</div>
    </div>`;
  }

  if (pages.length === 0) {
    return html`<div class="flex-1 flex flex-col">
      <${SectionHeader} title="Custom Pages" />
      <div class="p-5 text-gray-500 text-sm">
        No custom pages registered. See <span class="text-violet-400">guides/devtools-custom-pages.md</span> for setup instructions.
      </div>
    </div>`;
  }

  const widgets = pageData?.widgets || [];

  return html`
  <div class="flex-1 flex flex-col overflow-hidden">
    <${SectionHeader} title="Custom Pages" />
    <div class="flex flex-1 overflow-hidden">
      <div class="w-44 border-r border-gray-800 bg-gray-900/50 shrink-0 overflow-y-auto py-2">
        ${pages.map(p => html`
          <button key=${p.name}
            class="w-full text-left px-4 py-2 text-sm border-none cursor-pointer transition-colors
              ${selectedPage === p.name ? 'bg-violet-500/10 text-violet-400' : 'bg-transparent text-gray-500 hover:text-gray-300 hover:bg-gray-800/50'}"
            onClick=${() => setSelectedPage(p.name)}>
            ${p.name}
          </button>
        `)}
      </div>
      <div class="flex-1 overflow-y-auto p-5">
        ${pageData?.header_title && html`<h2 class="text-lg font-semibold text-gray-200 mb-4">${pageData.header_title}</h2>`}
        <div class="space-y-4">
          ${widgets.map(w => html`<${WidgetCard} key=${w.id} widget=${w} data=${widgetData[w.id]} openPopup=${w.eval?.enabled ? (ev, item) => setEvalModal({ ev, item, widgetId: w.id }) : null} />`)}
        </div>
      </div>
    </div>
    ${evalModal && html`<${EvalModal} widgetId=${evalModal.widgetId} eval=${evalModal.ev} item=${evalModal.item} onClose=${() => setEvalModal(null)} onRun=${async (code) => { setEvalModal({ ...evalModal, loading: true }); try { const res = await api('/api/devtools/eval', { body: { code, widget_id: evalModal.widgetId, item: JSON.stringify(evalModal.item) } }); setEvalModal({ ...evalModal, result: res, loading: false }); const w = widgets.find(w => w.id === evalModal.widgetId); if (w?.source) { const type = w.source.type; const key = w.source.key; const dataRes = await api('/api/devtools/data', { params: { type, key } }); setWidgetData(prev => ({ ...prev, [evalModal.widgetId]: dataRes.data })); } return res; } catch (e) { setEvalModal({ ...evalModal, result: { ok: false, error: e.message }, loading: false }); throw e; } }} />`}
  </div>
  `;
}

/* ── Single custom page view (rendered directly in main content area) ── */
function CustomPageView({ pageName, pageData }) {
  const [widgetData, setWidgetData] = useState({});
  const [popupState, setPopupState] = useState(null);

  // pageData has { name, definition } - definition has header_title and widgets
  const definition = pageData.definition || pageData;
  const widgets = definition.widgets || [];
  const headerTitle = definition.header_title || pageData.name;

  useEffect(() => {
    if (!widgets.length) return;
    async function fetchWidgetData() {
      const results = {};
      for (const w of widgets) {
        if (!w.source) continue;
        const type = w.source.type;
        const key = w.source.key;
        try {
          const res = await api('/api/devtools/data', { params: { type, key } });
          results[w.name] = res.data;
        } catch (e) {
          results[w.name] = null;
        }
      }
      setWidgetData(results);
    }
    fetchWidgetData();
  }, [pageName]);

  // Group widgets by row, default to "row1"
  const rowMap = {};
  widgets.forEach(w => {
    const row = w.row || 'row1';
    if (!rowMap[row]) rowMap[row] = [];
    rowMap[row].push(w);
  });
  const rows = Object.keys(rowMap).sort();

  return html`
  <div class="flex-1 flex flex-col overflow-hidden">
    <${SectionHeader} title=${headerTitle} />
    <div class="flex-1 overflow-y-auto p-5">
      ${rows.map(rowKey => html`
        <div key=${rowKey} class="flex gap-4 mb-4 flex-wrap w-full">
          ${rowMap[rowKey].map(w => html`
            <${WidgetCard}
              key=${w.name}
              widget=${w}
              data=${widgetData[w.name]}
              openPopup=${(ev, item) => setPopupState({ ev, item, widgetId: w.name })}
            />
          `)}
        </div>
      `)}
    </div>
    ${popupState && html`
      <${EvalModal}
        widgetId=${popupState.widgetId}
        eval=${popupState.ev}
        item=${popupState.item}
        onClose=${() => setPopupState(null)}
        onRun=${async (code) => {
        try {
          const res = await api('/api/devtools/eval', { body: { code, widget_id: popupState.widgetId, item: JSON.stringify(popupState.item) } });
          // Refresh widget data
          const w = widgets.find(w => w.name === popupState.widgetId);
          if (w?.source) {
            const type = w.source.type;
            const key = w.source.key;
            const dataRes = await api('/api/devtools/data', { params: { type, key } });
            setWidgetData(prev => ({ ...prev, [popupState.widgetId]: dataRes.data }));
          }
          return res;
        } catch (e) {
          throw e;
        }
      }}
      />
    `}
  </div>
  `;
}

/* ── Single widget card ── */
function WidgetCard({ widget, data, openPopup }) {
  const type = widget.type;
  const name = widget.name || widget.id;
  const options = widget.options || {};
  const eval_config = widget.eval || {};
  const color = options.color || null;
  const icon = options.icon || null;

  // Resolve icon: if string starting with '<svg', use directly; otherwise lookup in ICONS
  function resolveIcon(ic) {
    if (!ic) return null;
    if (typeof ic === 'string' && ic.trim().startsWith('<svg')) return html`<span dangerouslySetInnerHTML=${{ __html: ic }} />`;
    return ICONS[ic] || null;
  }

  const iconEl = resolveIcon(icon);
  const labelStyle = color ? { color } : {};

  if (type === 'stat') {
    const value = data;
    const show_delta = options.show_delta;
    const unit = options.unit || '';
    return html`
    <div class="bg-gray-900 border border-gray-800 rounded-lg p-4 flex-1 min-w-0">
      <div class="flex items-center gap-1.5 text-xs text-gray-500 mb-1">
        ${iconEl && html`<span style=${{ width: '14px', height: '14px', display: 'inline-flex', color }}>${iconEl}</span>`}
        <span style=${labelStyle}>${name}</span>
      </div>
      <div class="text-2xl font-semibold text-gray-100">${value ?? '—'}<span class="text-sm text-gray-400 ml-1">${unit}</span></div>
      ${show_delta && html`<div class="text-xs text-gray-500 mt-1">+0 (delta placeholder)</div>`}
    </div>
    `;
  }

  if (type === 'key_value') {
    const label = options.label || name;
    return html`
    <div class="bg-gray-900 border border-gray-800 rounded-lg p-4 flex-1 min-w-0">
      <div class="flex items-center gap-1.5 text-xs text-gray-500 mb-1">
        ${iconEl && html`<span style=${{ width: '14px', height: '14px', display: 'inline-flex', color }}>${iconEl}</span>`}
        <span style=${labelStyle}>${label}</span>
      </div>
      <div class="text-lg text-gray-100">${inspectVal(data)}</div>
      ${eval_config.enabled && html`
        <button class="mt-2 px-2 py-1 text-xs bg-gray-800 hover:bg-gray-700 text-gray-300 rounded border-none cursor-pointer"
          onClick=${() => openPopup && openPopup(eval_config, null)}>Eval</button>
      `}
    </div>
    `;
  }

  if (type === 'table') {
    const columns = widget.columns || [];
    const items = Array.isArray(data) ? data : [];
    const evals = widget.evals || (widget.eval ? [widget.eval] : []);
    return html`
    <div class="bg-gray-900 border border-gray-800 rounded-lg p-4 flex-1 min-w-0">
      <div class="flex items-center justify-between px-4 py-2 border-b border-gray-800 shrink-0">
        <div class="flex items-center gap-1.5">
          ${iconEl && html`<span style=${{ width: '14px', height: '14px', display: 'inline-flex', color }}>${iconEl}</span>`}
          <span class="text-sm font-medium text-gray-300" style=${labelStyle}>${name}</span>
        </div>
      </div>
      <table class="w-full text-sm">
        <thead>
          <tr>${columns.map(c => html`<th key=${c.key} class="px-3 py-2 text-left text-xs text-gray-500 border-b border-gray-800 font-medium shrink-0">${c.label}</th>`)}
            ${evals.length > 0 && html`<th class="px-3 py-2 text-left text-xs text-gray-500 border-b border-gray-800 font-medium shrink-0">Actions</th>`}
          </tr>
        </thead>
        <tbody>
          ${items.map((row, i) => html`
            <tr key=${i} class="border-b border-gray-800/50 hover:bg-gray-800/30">${columns.map(c => html`<td key=${c.key} class="px-3 py-2 text-gray-300 font-mono text-xs shrink-0">${inspectVal(row[c.key])}</td>`)}
              ${evals.length > 0 && html`
                <td class="px-3 py-2 shrink-0">
                  <div class="flex gap-1 flex-wrap">
                    ${evals.map((ev, ei) => html`<${EvalButton} key=${ei} eval=${ev} item=${row} widgetId=${name} openPopup=${openPopup} />`)}
                  </div>
                </td>
              `}
            </tr>
          `)}
        </tbody>
      </table>
    </div>
    `;
  }

  if (type === 'list') {
    const items = Array.isArray(data) ? data : [];
    const max = options.max_items || 100;
    const template = options.item_template;
    const evals = widget.evals || (widget.eval ? [widget.eval] : []);
    return html`
    <div class="bg-gray-900 border border-gray-800 rounded-lg overflow-hidden flex-1 min-w-0">
      <div class="flex items-center justify-between px-4 py-2 border-b border-gray-800 shrink-0">
        <div class="flex items-center gap-1.5">
          ${iconEl && html`<span style=${{ width: '14px', height: '14px', display: 'inline-flex', color }}>${iconEl}</span>`}
          <span class="text-sm font-medium text-gray-300" style=${labelStyle}>${name}</span>
        </div>
      </div>
      <ul class="divide-y divide-gray-800/50 max-h-64 overflow-y-auto">
        ${items.slice(0, max).map((item, i) => html`
          <li key=${i} class="px-4 py-2 text-sm text-gray-300 flex items-center justify-between gap-2">
            <span class="flex-1">${template ? renderTemplate(item, template) : inspectVal(item)}</span>
            ${evals.length > 0 && html`
              <span class="flex gap-1 shrink-0">
                ${evals.map((ev, ei) => html`<${EvalButton} key=${ei} eval=${ev} item=${item} widgetId=${name} openPopup=${openPopup} inline=${true} />`)}
              </span>
            `}
          </li>
        `)}
      </ul>
    </div>
    `;
  }

  if (type === 'chart_line') {
    return html`
    <div class="bg-gray-900 border border-gray-800 rounded-lg p-4 flex-1 min-w-0">
      <div class="flex items-center gap-1.5 text-sm font-medium text-gray-300 mb-3">
        ${iconEl && html`<span style=${{ width: '14px', height: '14px', display: 'inline-flex', color }}>${iconEl}</span>`}
        <span style=${labelStyle}>${name}</span>
      </div>
      <div class="text-xs text-gray-500 text-center py-8">(chart placeholder)</div>
    </div>
    `;
  }

  if (type === 'html') {
    return html`
    <div class="bg-gray-900 border border-gray-800 rounded-lg p-4">
      <div class="text-sm font-medium text-gray-300 mb-2">${widget.id}</div>
      <div class="text-sm text-gray-300">${widget.template || ''}</div>
    </div>
    `;
  }

  // Fallback
  return html`
  <div class="bg-gray-900 border border-gray-800 rounded-lg p-4">
    <div class="text-sm text-gray-500">Unknown widget type: ${type}</div>
  </div>
  `;
}

/* ── Inspect value for display ── */
function inspectVal(v) {
  if (v === null || v === undefined) return '—';
  if (typeof v === 'object') return JSON.stringify(v);
  return String(v);
}

/* ── Render template with %key% substitution ── */
function renderTemplate(item, template) {
  if (typeof item !== 'object') return inspectVal(item);
  return template.replace(/%([^%]+)%/g, (_, k) => {
    const val = item[k.trim()] || '';
    return inspectVal(val);
  });
}

/* ── Per-row eval button ── */
function EvalButton({ eval: ev, item, widgetId, inline, openPopup }) {
  const [result, setResult] = useState(null);
  const [loading, setLoading] = useState(false);

  async function handleRun(code) {
    setLoading(true);
    setResult(null);
    try {
      const res = await api('/api/devtools/eval', {
        body: { code, widget_id: widgetId, item: JSON.stringify(item) }
      });
      setResult(res);
    } catch (e) {
      setResult({ ok: false, error: e.message });
    } finally {
      setLoading(false);
    }
  }

  const label = ev.label || 'Eval';
  const defaultCode = ev.default_code || 'item';
  const confirm = ev.confirm || null;

  // Popup mode button — opens centered modal via openPopup
  return html`
    <button class="px-2 py-1 text-xs bg-gray-800 hover:bg-gray-700 text-gray-300 rounded border-none cursor-pointer shrink-0"
      onClick=${() => openPopup && openPopup(ev, item)}>
      ${label}
    </button>
  `;
}

/* ── Eval Modal ── */
function EvalModal({ widgetId, eval: ev, item, onClose, onRun }) {
  const [code, setCode] = useState(ev?.default_code || 'item');
  const [result, setResult] = useState(null);
  const [loading, setLoading] = useState(false);

  async function handleRun() {
    setLoading(true);
    setResult(null);
    try {
      const res = await onRun(code);
      setResult(res);
    } catch (e) {
      setResult({ ok: false, error: e.message });
    } finally {
      setLoading(false);
    }
  }

  return html`
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/60">
    <div class="bg-gray-900 border border-gray-700 rounded-lg w-full max-w-2xl mx-4 max-h-[80vh] flex flex-col">
      <div class="flex items-center justify-between px-4 py-3 border-b border-gray-700">
        <span class="text-sm font-medium text-gray-200">${ev?.label || 'Eval'}: ${widgetId}</span>
        <button class="text-gray-500 hover:text-gray-300 text-lg border-none bg-transparent cursor-pointer"
          onClick=${onClose}>X</button>
      </div>
      <div class="flex-1 overflow-y-auto p-4 space-y-3">
        ${item && html`<div class="text-xs text-gray-500">Row data: <code class="text-violet-400">item</code> = ${inspectVal(item)}</div>`}
        <textarea
          class="w-full h-32 px-3 py-2 bg-gray-950 border border-gray-800 text-xs text-gray-200 font-mono resize-none"
          value=${code}
          onInput=${e => setCode(e.target.value)}
        ></textarea>
        ${result && html`
          <div class="text-xs">
            ${result.ok === false && html`<div class="text-red-400">Error: ${result.error}</div>`}
            ${result.ok === true && html`<div class="text-emerald-400">Result: ${inspectVal(result.result)}</div>`}
          </div>
        `}
      </div>
      <div class="flex justify-end gap-2 px-4 py-3 border-t border-gray-700">
        <button class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 text-gray-300 text-xs rounded border-none cursor-pointer"
          onClick=${onClose}>Cancel</button>
        <button class="px-3 py-1.5 bg-violet-600 hover:bg-violet-700 text-white text-xs rounded border-none cursor-pointer"
          onClick=${handleRun} disabled=${loading}>
          ${loading ? 'Running...' : 'Run'}
        </button>
      </div>
    </div>
  </div>
  `;
}
