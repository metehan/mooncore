/* ─── App ─── */
function App() {
  const [page, setPage] = useState('dashboard');
  const [editFile, setEditFile] = useState(null);
  const [editedContent, setEditedContent] = useState('');
  const [dirty, setDirty] = useState(false);
  const [saving, setSaving] = useState(false);
  const [evalResult, setEvalResult] = useState(null);
  const [pendingLoad, setPendingLoad] = useState(null);
  const [consoleInput, setConsoleInput] = useState('');
  const [consoleHistory, setConsoleHistory] = useState([]);
  const [consoleCmdHistory, setConsoleCmdHistory] = useState([]);

  function openFile(fileData) {
    setEditFile(fileData);
    setEditedContent(fileData.content);
    setDirty(false);
    setEvalResult(null);
  }

  function closeFile() {
    setEditFile(null);
    setEditedContent('');
    setDirty(false);
    setEvalResult(null);
  }

  async function saveFile() {
    if (!editFile || !dirty) return;
    setSaving(true);
    await api('/api/file', { method: 'PUT', body: { path: editFile.path, content: editedContent } });
    setEditFile({ ...editFile, content: editedContent });
    setDirty(false);
    setSaving(false);
  }

  function onEdit(val) {
    setEditedContent(val);
    setDirty(val !== editFile.content);
  }

  async function evalCode() {
    const r = await api('/api/eval', { body: { code: editedContent } });
    setEvalResult(r);
  }

  function loadToRunner(data) {
    const actionName = data.action || '';
    // Build prefilled params: required validate fields + overrides
    let p = {};
    if (data.overrides && typeof data.overrides === 'object') {
      Object.entries(data.overrides).forEach(([k, v]) => { p[k] = v; });
    }
    if (Array.isArray(data.validate)) {
      data.validate.forEach(item => {
        const field = item && typeof item === 'object' ? item.name : (Array.isArray(item) ? item[0] : item);
        const rules = item && typeof item === 'object' ? (item.rules || []) : (Array.isArray(item) ? item[1] : []);
        const required = Array.isArray(rules) && rules.includes('required');
        if (required) p[field] = '';
      });
    }
    setPendingLoad({ action: actionName, params: Object.keys(p).length ? JSON.stringify(p, null, 2) : '{}', auth: data.auth ? JSON.stringify(data.auth, null, 2) : '' });
    setPage('api');
  }

  function toEval(action, paramsJson, authJson) {
    const code = buildElixirCall(action, paramsJson, authJson);
    setConsoleInput(code);
    setPage('console');
  }

  const showRight = editFile;

  return html`
<div class="flex flex-1 overflow-hidden h-screen">
  <!-- Left Menu -->
  <div class="w-44 border-r border-gray-800 bg-gray-900 flex flex-col shrink-0">
    <button class="px-4 py-3 border-b border-gray-800 flex items-center gap-2.5 bg-transparent border-x-0 border-t-0 cursor-pointer text-left hover:bg-gray-800/40 transition-colors"
      onClick=${() => setPage('dashboard')}>
      <${MoonCanvas} size=${28} />
      <span class="text-sm font-bold text-violet-400">Mooncore</span>
    </button>
    <nav class="flex-1 py-2">
      ${MENU.map(m => html`
        <button key=${m.id}
          class="w-full text-left px-4 py-2 text-sm flex items-center gap-2.5 border-none cursor-pointer transition-colors
            ${page === m.id ? 'bg-violet-500/10 text-violet-400' : 'bg-transparent text-gray-500 hover:text-gray-300 hover:bg-gray-800/50'}"
          onClick=${() => setPage(m.id)}>
          <span class="w-5 text-center flex items-center justify-center">${ICONS[m.id]}</span>
          ${m.label}
        </button>
      `)}
    </nav>
    <div class="px-4 py-3 border-t border-gray-800">
      <div class="text-xs text-gray-600">Mooncore Dev</div>
    </div>
  </div>

  <!-- Center Content -->
  <div class="flex-1 overflow-y-auto min-w-0">
    ${page === 'dashboard' && html`<${DashboardPage} />`}
    ${page === 'api' && html`<${ApiPage} pendingLoad=${pendingLoad} onConsumePendingLoad=${() => setPendingLoad(null)} onToEval=${toEval} />`}
    ${page === 'tools' && html`<${ToolsPage} />`}
    ${page === 'guides' && html`<${GuidesPage} />`}
    ${page === 'ets' && html`<${EtsPage} />`}
    ${page === 'clients' && html`<${ClientsPage} />`}
    ${page === 'sockets' && html`<${SocketsPage} />`}
    ${page === 'console' && html`<${ConsolePage} initialInput=${consoleInput} onConsumeInput=${() => setConsoleInput('')}
      history=${consoleHistory} setHistory=${setConsoleHistory}
      cmdHistory=${consoleCmdHistory} setCmdHistory=${setConsoleCmdHistory} />`}
    ${page === 'files' && html`<${FilesPage} onOpenFile=${openFile} />`}
  </div>

  <!-- Right Panel: action logs on Runner, file editor when file open -->
  ${showRight && html`
    <div class="border-l border-gray-800 bg-gray-900 flex flex-col shrink-0 overflow-hidden" style="width: 60%; max-width: 60%">
      ${editFile
        ? html`<${EditorPanel} key=${editFile.path} file=${editFile} edited=${editedContent} dirty=${dirty} saving=${saving}
            evalResult=${evalResult} onEdit=${onEdit} onSave=${saveFile} onClose=${closeFile} onEval=${evalCode} />`
        : html`<${ActionLogsPanel} onReplay=${loadToRunner} />`
      }
    </div>
  `}
</div>
  `;
}

/* ─── Section header ─── */
