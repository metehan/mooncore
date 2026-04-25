function ConsolePage({ initialInput, onConsumeInput, history, setHistory, cmdHistory, setCmdHistory }) {
  const [input, setInput] = useState('');
  const [histIdx, setHistIdx] = useState(-1);
  const [loading, setLoading] = useState(false);
  const outRef = useRef(null);
  const inputRef = useRef(null);

  useEffect(() => {
    if (initialInput) {
      setInput(initialInput);
      if (onConsumeInput) onConsumeInput();
      setTimeout(() => { if (inputRef.current) inputRef.current.focus(); }, 50);
    }
  }, [initialInput]);

  async function exec() {
    if (!input.trim()) return;
    setLoading(true);
    const cmd = input;
    setCmdHistory(prev => [cmd, ...prev]);
    setHistIdx(-1);
    setHistory(prev => [...prev, { type: 'input', text: cmd }]);
    setInput('');
    const r = await api('/api/eval', { body: { code: cmd } });
    setHistory(prev => [...prev, { type: r.ok ? 'output' : 'error', text: r.ok ? r.result : r.error }]);
    setLoading(false);
    setTimeout(() => { if (outRef.current) outRef.current.scrollTop = outRef.current.scrollHeight; }, 50);
  }

  function onKey(e) {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); exec(); }
    if (e.key === 'ArrowUp') { e.preventDefault(); const n = Math.min(histIdx + 1, cmdHistory.length - 1); setHistIdx(n); setInput(cmdHistory[n] || ''); }
    if (e.key === 'ArrowDown') { e.preventDefault(); const n = Math.max(histIdx - 1, -1); setHistIdx(n); setInput(n === -1 ? '' : cmdHistory[n] || ''); }
  }

  return html`
  <div class="flex flex-col h-full">
  <${SectionHeader} title="IEx Console" />
  <div ref=${outRef}
    class="flex-1 bg-gray-950 text-gray-300 text-xs overflow-y-auto p-4 font-mono whitespace-pre-wrap">
    <div class="text-gray-600 mb-2">Interactive Elixir \u2014 evaluate code in the running application</div>
    ${history.map(h => html`
      <div style="color:${h.type === 'input' ? '#a78bfa' : h.type === 'error' ? '#f87171' : '#4ade80'}" class="py-px leading-relaxed">
        ${h.type === 'input' ? html`<span class="text-gray-600">iex> </span>` : ''}${h.text}
      </div>
    `)}
    ${loading && html`<div class="py-1"><span class="spinner"></span></div>`}
  </div>
  <div class="flex gap-2 items-center px-3 py-2 border-t border-gray-800">
    <span class="text-violet-400 font-mono text-xs">iex></span>
    <input ref=${inputRef} class="flex-1 px-2 py-1.5 bg-gray-950 border border-gray-800 text-xs text-gray-200 font-mono"
      value=${input} onInput=${e => setInput(e.target.value)} onKeyDown=${onKey}
      placeholder="Enum.map(1..5, & &1 * 2)" autocomplete="off" />
    <button class="px-3 py-1.5 bg-violet-600 hover:bg-violet-700 text-white text-xs rounded cursor-pointer border-none"
      onClick=${exec} disabled=${loading}>Run</button>
  </div>
</div>
  `;
}

/* ─── Files Page (browser only) ─── */
