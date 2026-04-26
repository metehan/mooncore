function displayName(name) {
  if (!name) return '';
  return name.replace(/\.md$/i, '').replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
}

function GuidesPage() {
  const [guides, setGuides] = useState([]);
  const [selected, setSelected] = useState(null);
  const [selectedFile, setSelectedFile] = useState(null);
  const [content, setContent] = useState('');
  const [originalContent, setOriginalContent] = useState('');
  const [loading, setLoading] = useState(true);
  const [guideLoading, setGuideLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [dirty, setDirty] = useState(false);
  const [viewMode, setViewMode] = useState('preview');
  const [guideQuery, setGuideQuery] = useState('');
  const editorRef = useRef(null);
  const cmRef = useRef(null);
  const saveRef = useRef(null);

  useEffect(() => {
    let active = true;

    api('/api/guides').then(d => {
      if (!active) return;
      const items = d.guides || [];
      setGuides(items);
      setLoading(false);
      if (items.length > 0 && !selectedFile) {
        loadGuide(items[0]);
      }
    });

    return () => {
      active = false;
      if (cmRef.current) {
        cmRef.current = destroyCodeMirror(cmRef.current);
      }
    };
  }, []);

  async function loadGuide(g) {
    setSelected(g.name);
    setSelectedFile(g.file);
    setGuideLoading(true);
    setDirty(false);
    setViewMode('preview');
    if (cmRef.current) cmRef.current = destroyCodeMirror(cmRef.current);
    const d = await api('/api/guide?name=' + encodeURIComponent(g.file));
    const c = d.content || '';
    setContent(c);
    setOriginalContent(c);
    setGuideLoading(false);
  }

  useEffect(() => {
    if (viewMode !== 'edit') {
      if (cmRef.current) cmRef.current = destroyCodeMirror(cmRef.current);
      return;
    }
    if (!selected || !editorRef.current || cmRef.current) return;

    const cm = CodeMirror(editorRef.current, {
      value: content,
      mode: 'markdown',
      theme: 'material-darker',
      lineNumbers: true,
      tabSize: 2,
      indentUnit: 2,
      indentWithTabs: false,
      lineWrapping: true,
      extraKeys: {
        'Ctrl-S': () => { if (saveRef.current) saveRef.current(); },
        'Cmd-S': () => { if (saveRef.current) saveRef.current(); },
        Tab: (cm) => cm.replaceSelection('  ', 'end'),
      }
    });
    cm.on('change', () => {
      const val = cm.getValue();
      setContent(val);
      setDirty(val !== originalContent);
    });
    cmRef.current = cm;
    setTimeout(() => cm.refresh(), 1);
    return () => {
      if (cmRef.current === cm) cmRef.current = destroyCodeMirror(cm);
    };
  }, [selectedFile, viewMode]);

  useEffect(() => {
    if (viewMode === 'edit' && cmRef.current && cmRef.current.getValue() !== content) {
      cmRef.current.setValue(content);
      setTimeout(() => cmRef.current && cmRef.current.refresh(), 1);
    }
  }, [content, viewMode, selectedFile]);

  async function saveGuide() {
    if (!selectedFile) return;
    const val = cmRef.current ? cmRef.current.getValue() : content;
    setSaving(true);
    await api('/api/file', { method: 'PUT', body: { path: 'guides/' + selectedFile, content: val } });
    setOriginalContent(val);
    setContent(val);
    setDirty(false);
    setSaving(false);
  }
  saveRef.current = saveGuide;

  if (loading) return html`<div class="p-8"> <span class="spinner"></span></div> `;

  return html`
  <div class="h-full flex min-h-0">
    <div class="w-56 border-r border-gray-800 bg-gray-900/50 shrink-0 flex flex-col">
      <${SectionHeader} title="Guides" count=${guides.length} />
      <div class="px-4 py-3 border-b border-gray-800 bg-gray-950/40">
        <input value=${guideQuery} onInput=${e => setGuideQuery(e.target.value)} placeholder="Filter guides"
          class="w-full bg-gray-950 border border-gray-800 rounded-lg px-3 py-2 text-xs text-gray-200" />
      </div>
      <div class="flex-1 overflow-y-auto">
        ${guides.filter(g => !guideQuery || displayName(g.name).toLowerCase().includes(guideQuery.toLowerCase())).length === 0
      ? html`<div class="p-5 text-xs text-gray-600">No guides match.</div>`
      : guides.filter(g => !guideQuery || displayName(g.name).toLowerCase().includes(guideQuery.toLowerCase())).map(g => html`
            <button key=${g.file}
              class="group w-full text-left px-4 py-2 bg-transparent border-x-0 border-t-0 border-b border-gray-800/30 cursor-pointer transition-colors
                ${selectedFile === g.file ? 'bg-violet-500/10' : 'hover:bg-gray-800/40'}"
              onClick=${() => loadGuide(g)}>
              <div class="flex items-center gap-2">
                <span class="${selectedFile === g.file ? 'text-violet-400' : 'text-gray-500 group-hover:text-gray-300'}">\uD83D\uDCD6</span>
                <div class="text-xs ${selectedFile === g.file ? 'text-violet-300' : 'text-gray-300'} truncate">${displayName(g.name)}</div>
              </div>
            </button>
          `)
    }
      </div>
    </div>

    <div class="flex-1 min-w-0 flex flex-col">
      <div class="px-4 py-3 border-b border-gray-800 flex items-center gap-3 bg-gray-900/50 shrink-0">
        <div class="min-w-0 flex-1">
          <div class="text-xs font-semibold text-gray-400 uppercase tracking-wider truncate">${displayName(selected)}</div>
        </div>
        <div class="flex items-center gap-1 rounded-lg bg-gray-900 border border-gray-800 p-1">
          <button class="px-2.5 py-1 text-xs rounded border-none cursor-pointer transition-colors ${viewMode === 'preview' ? 'bg-violet-600 text-white' : 'bg-transparent text-gray-500 hover:text-gray-300'}"
            onClick=${() => setViewMode('preview')}>Preview</button>
          <button class="px-2.5 py-1 text-xs rounded border-none cursor-pointer transition-colors ${viewMode === 'edit' ? 'bg-violet-600 text-white' : 'bg-transparent text-gray-500 hover:text-gray-300'}"
            onClick=${() => setViewMode('edit')}>Edit</button>
        </div>
        ${dirty && html`<span class="text-xs text-amber-400">\u25CF</span>`}
        <button class="px-2.5 py-1 text-xs rounded border-none cursor-pointer transition-colors
          ${dirty ? 'bg-violet-600 hover:bg-violet-700 text-white' : 'bg-gray-800 text-gray-600 cursor-default'}"
          onClick=${saveGuide} disabled=${!dirty || saving}>
          ${saving ? html`<span class="spinner mr-1" style="width:10px;height:10px;border-width:1.5px"></span>` : ''} Save
        </button>
      </div>

      <div class="flex-1 min-h-0 overflow-hidden">
        ${guideLoading
      ? html`<div class="p-5"><span class="spinner"></span></div>`
      : viewMode === 'edit'
        ? html`<div class="cm-wrap h-full" ref=${editorRef}></div>`
        : html`
              <div class="h-full overflow-y-auto">
                ${content ? html`<${MarkdownRenderer} content=${content} />` : html`<div class="p-5 text-sm text-gray-600">Select a guide to preview it.</div>`}
              </div>
            `
    }
      </div>
    </div>
  </div>
  `;
}

/* ─── Markdown Renderer with evaluable code blocks ─── */
function MarkdownRenderer({ content }) {
  const blocks = useMemo(() => parseMarkdown(content), [content]);
  return html`<div class="guide-content px-6 py-5 space-y-4"> ${blocks.map((b, i) => html`<${MarkdownBlock} key=${i} block=${b} />`)}</div> `;
}

function parseMarkdown(md) {
  const blocks = [];
  const lines = md.split('\n');
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const codeMatch = line.match(/^\x60\x60\x60(\w*)/);
    if (codeMatch) {
      const lang = codeMatch[1] || '';
      const codeLines = [];
      i++;
      while (i < lines.length && !lines[i].match(/^\x60\x60\x60\s*$/)) {
        codeLines.push(lines[i]);
        i++;
      }
      i++; // skip closing ```
      blocks.push({ type: 'code', lang, code: codeLines.join('\n') });
    } else if (line.trim() === '') {
      i++;
    } else {
      // Collect consecutive text lines
      const textLines = [];
      while (i < lines.length && !lines[i].match(/^\x60\x60\x60/) && lines[i].trim() !== '') {
        textLines.push(lines[i]);
        i++;
      }
      const text = textLines.join('\n');
      // Detect heading
      const hMatch = text.match(/^(#{1,6})\s+(.*)/);
      if (hMatch) {
        blocks.push({ type: 'heading', level: hMatch[1].length, text: hMatch[2] });
      } else {
        blocks.push({ type: 'text', text });
      }
    }
  }
  return blocks;
}

function MarkdownBlock({ block }) {
  if (block.type === 'heading') {
    const sizes = { 1: 'text-xl', 2: 'text-lg', 3: 'text-base', 4: 'text-sm', 5: 'text-xs', 6: 'text-xs' };
    const mt = block.level <= 2 ? 'mt-6' : 'mt-3';
    return html`<div class="${sizes[block.level] || 'text-sm'} font-semibold text-gray-200 ${mt}">${renderInline(block.text)}</div>`;
  }
  if (block.type === 'code') {
    return html`<${EvalCodeBlock} lang=${block.lang} code=${block.code} />`;
  }
  // text
  return html`<p class="text-sm text-gray-400 leading-relaxed">${renderInline(block.text)}</p>`;
}

function renderInline(text) {
  // Split on inline code `...`
  const parts = text.split(/(\x60[^\x60]+\x60)/g);
  return parts.map((p, i) => {
    if (p.startsWith('\x60') && p.endsWith('\x60')) {
      return html`<code key=${i} class="px-1 py-0.5 bg-gray-800 text-violet-400 text-xs rounded">${p.slice(1, -1)}</code>`;
    }
    // Bold
    const boldParts = p.split(/(\*\*[^*]+\*\*)/g);
    return boldParts.map((bp, j) => {
      if (bp.startsWith('**') && bp.endsWith('**')) {
        return html`<strong key=${j} class="text-gray-200">${bp.slice(2, -2)}</strong>`;
      }
      return bp;
    });
  });
}

function EvalCodeBlock({ lang, code }) {
  const [result, setResult] = useState(null);
  const [loading, setLoading] = useState(false);
  const [editedCode, setEditedCode] = useState(code);
  const editorRef = useRef(null);
  const cmRef = useRef(null);
  const editedRef = useRef(editedCode);
  editedRef.current = editedCode;

  const isEval = ['elixir', 'ex', 'exs', 'iex'].includes(lang) || lang === '';
  const lineCount = editedCode.split('\n').length;
  const largeBlock = lineCount > 24 || editedCode.length > 1200;

  const modeMap = {
    elixir: 'ruby', ex: 'ruby', exs: 'ruby', iex: 'ruby', erl: 'erlang',
    js: 'javascript', javascript: 'javascript', json: { name: 'javascript', json: true },
    html: 'htmlmixed', css: 'css', md: 'markdown', shell: 'shell', bash: 'shell',
    yaml: 'yaml', xml: 'xml'
  };

  useEffect(() => {
    if (!editorRef.current || cmRef.current) return;
    const cm = CodeMirror(editorRef.current, {
      value: code,
      mode: modeMap[lang] || null,
      theme: 'material-darker',
      lineNumbers: true,
      tabSize: 2,
      indentUnit: 2,
      indentWithTabs: false,
      lineWrapping: false,
      viewportMargin: Infinity,
      scrollbarStyle: 'null',
    });
    cm.setSize(null, null); // auto height
    cm.on('change', () => {
      const val = cm.getValue();
      editedRef.current = val;
      setEditedCode(val);
    });
    cmRef.current = cm;
    setTimeout(() => cm.refresh(), 1);
  }, []);

  async function evalBlock() {
    setLoading(true);
    const r = await api('/api/eval', { body: { code: editedRef.current } });
    setResult(r);
    setLoading(false);
  }

  return html`
  <div class="border border-gray-800 overflow-hidden group/eval relative ${loading ? 'eval-running' : ''}">
    <div class="cm-wrap-block" ref=${editorRef}></div>
    ${isEval && html`
      <button class="eval-run-btn absolute top-1 right-1 w-6 h-6 flex items-center justify-center rounded
        border-none cursor-pointer transition-all opacity-0 group-hover/eval:opacity-100
        ${loading ? 'bg-gray-700 text-gray-400' : 'bg-gray-800/80 hover:bg-violet-600 text-gray-400 hover:text-white'}"
        onClick=${evalBlock} disabled=${loading} title="Evaluate">
        ${loading ? html`<span class="spinner" style="width:8px;height:8px;border-width:1.5px"></span>` : html`<span style="font-size:10px">▶</span>`}
      </button>
    `}
    ${result && html`
      <div class="px-3 py-2 bg-gray-950 border-t border-gray-800 flex items-start gap-2">
        <span class="text-xs mt-px ${result.ok ? 'text-emerald-400' : 'text-red-400'}">${result.ok ? '\u2713' : '\u2717'}</span>
        <pre class="text-xs font-mono whitespace-pre-wrap flex-1 ${result.ok ? 'text-emerald-400' : 'text-red-400'}">${result.ok ? result.result : result.error}</pre>
      </div>
    `}
  </div>
`;
}

/* ─── Right Panel: File Editor ─── */
