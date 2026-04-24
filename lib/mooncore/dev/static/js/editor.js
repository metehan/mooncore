function EditorPanel({ file, edited, dirty, saving, evalResult, onEdit, onSave, onClose, onEval }) {
  const editorRef = useRef(null);
  const cmRef = useRef(null);
  const onEditRef = useRef(onEdit);
  const onSaveRef = useRef(onSave);
  onEditRef.current = onEdit;
  onSaveRef.current = onSave;

  const ext = file.path.split('.').pop();
  const isElixir = ['ex', 'exs'].includes(ext);
  const langLabel = {
    ex: 'Elixir', exs: 'Elixir', erl: 'Erlang', js: 'JavaScript', ts: 'TypeScript',
    json: 'JSON', html: 'HTML', css: 'CSS', md: 'Markdown', txt: 'Text', yml: 'YAML', yaml: 'YAML',
    toml: 'TOML', xml: 'XML', sh: 'Shell'
  }[ext] || ext.toUpperCase();

  const modeMap = {
    ex: 'ruby', exs: 'ruby', erl: 'erlang',
    js: 'javascript', ts: 'javascript', json: { name: 'javascript', json: true },
    html: 'htmlmixed', css: 'css', md: 'markdown',
    yml: 'yaml', yaml: 'yaml', xml: 'xml', sh: 'shell'
  };

  useEffect(() => {
    if (!editorRef.current || cmRef.current) return;
    const cm = CodeMirror(editorRef.current, {
      value: edited || '',
      mode: modeMap[ext] || null,
      theme: 'material-darker',
      lineNumbers: true,
      tabSize: 2,
      indentUnit: 2,
      indentWithTabs: false,
      lineWrapping: false,
      matchBrackets: true,
      extraKeys: {
        'Ctrl-S': () => onSaveRef.current(),
        'Cmd-S': () => onSaveRef.current(),
        Tab: (cm) => cm.replaceSelection('  ', 'end'),
      }
    });
    cm.on('change', () => onEditRef.current(cm.getValue()));
    cmRef.current = cm;
    setTimeout(() => cm.refresh(), 1);
  }, []);

  useEffect(() => {
    if (cmRef.current && cmRef.current.getValue() !== edited) {
      cmRef.current.setValue(edited || '');
    }
  }, [edited]);

  return html`
<div class="flex flex-col h-full">
  <div class="px-3 py-2 border-b border-gray-800 flex items-center gap-2 shrink-0">
    <button class="text-gray-500 hover:text-gray-300 bg-transparent border-none cursor-pointer text-sm" onClick=${onClose}>\u2715</button>
    <code class="text-xs text-violet-400 flex-1 truncate">${file.path}</code>
    <span class="text-xs text-gray-600">${langLabel}</span>
    ${dirty && html`<span class="text-xs text-amber-400">\u25CF</span>`}
    ${isElixir && html`
      <button class="px-2 py-1 text-xs rounded border-none cursor-pointer transition-colors bg-amber-600 hover:bg-amber-700 text-white"
        onClick=${onEval}>Eval</button>
    `}
    <button class="px-2 py-1 text-xs rounded border-none cursor-pointer transition-colors
      ${dirty ? 'bg-violet-600 hover:bg-violet-700 text-white' : 'bg-gray-800 text-gray-600 cursor-default'}"
      onClick=${onSave} disabled=${!dirty || saving}>
      ${saving ? html`<span class="spinner mr-1"></span>` : ''} Save
    </button>
  </div>
  <div class="cm-wrap flex-1 min-h-0" ref=${editorRef}></div>
  ${evalResult && html`
    <div class="border-t border-gray-800 px-3 py-2 bg-gray-950 shrink-0 max-h-32 overflow-y-auto">
      <div class="flex items-center gap-2 mb-1">
        <span class="text-xs font-semibold ${evalResult.ok ? 'text-emerald-400' : 'text-red-400'}">
          ${evalResult.ok ? 'Result' : 'Error'}
        </span>
      </div>
      <pre class="text-xs ${evalResult.ok ? 'text-gray-400' : 'text-red-400'} whitespace-pre-wrap">${evalResult.ok ? evalResult.result : evalResult.error}</pre>
    </div>
  `}
</div>
  `;
}

render(html`<${App} />`, document.getElementById('app'));
// Dismiss preloader only after Preact has rendered and the browser has painted.
// Also enforce a minimum 1000ms display so the moon canvas loader is visible.
var minStart = Date.now();
requestAnimationFrame(function () {
  requestAnimationFrame(function () {
    var elapsed = Date.now() - minStart;
    var remaining = 1000 - elapsed;
    setTimeout(function () {
      if (window.__dismissPreloader) window.__dismissPreloader();
    }, Math.max(0, remaining));
  });
});
