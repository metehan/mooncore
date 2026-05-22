function ToolsPage() {
  const [tab, setTab] = useState('json');
  const tabs = [
    { id: 'json', label: 'JSON \u2194 Elixir' },
    { id: 'jwt', label: 'JWT Token' },
    { id: 'base64', label: 'Base64' },
    { id: 'timestamp', label: 'Timestamps' },
    { id: 'inspect', label: 'Inspect' },
  ];
  return html`
  <div class="h-full flex flex-col">
  <${SectionHeader} title="Tools" />
  <div class="flex border-b border-gray-800 px-3 shrink-0">
    ${tabs.map(t => html`
      <button key=${t.id}
        class="px-3 py-2 text-xs border-none cursor-pointer transition-colors
          ${tab === t.id ? 'text-violet-400 border-b-2 border-violet-400 bg-transparent' : 'text-gray-500 hover:text-gray-300 bg-transparent'}"
        style=${tab === t.id ? 'box-shadow: inset 0 -2px 0 #7c3aed' : ''}
        onClick=${() => setTab(t.id)}>${t.label}</button>
    `)}
  </div>
  <div class="flex-1 overflow-y-auto">
    ${tab === 'json' && html`<${ToolJsonElixir} />`}
    ${tab === 'jwt' && html`<${ToolJwt} />`}
    ${tab === 'base64' && html`<${ToolBase64} />`}
    ${tab === 'timestamp' && html`<${ToolTimestamp} />`}
    ${tab === 'inspect' && html`<${ToolInspect} />`}
  </div>
</div>
  `;
}

/* ── Tool: JSON <-> Elixir Map ── */
function elixirToJson(str) {
  // Basic Elixir map/list to JSON conversion
  let s = str.trim();
  // %{} -> {}
  s = s.replace(/%\{/g, '{');
  // atom keys like foo: val -> "foo": val
  s = s.replace(/(\{|,)\s*([a-z_][a-z0-9_?!]*)\s*:/g, '$1 "$2":');
  // string keys "key" => val -> "key": val
  s = s.replace(/=>/g, ':');
  // nil -> null
  s = s.replace(/\bnil\b/g, 'null');
  // :atom_values -> "atom_values"
  s = s.replace(/:([a-z_][a-z0-9_?!]*)/g, '"$1"');
  // true/false stay the same
  return s;
}

function ToolJsonElixir() {
  const [left, setLeft] = useState('{\n  "name": "Alice",\n  "age": 30,\n  "active": true\n}');
  const [right, setRight] = useState('');
  const [direction, setDirection] = useState('toElixir'); // toElixir | toJson

  function convertToElixir() {
    try {
      const parsed = JSON.parse(left);
      setRight(jsonToElixir(parsed));
      setDirection('toElixir');
    } catch (e) {
      setRight('# Error: ' + e.message);
    }
  }

  function convertToJson() {
    try {
      const result = elixirToJson(left);
      // Try to parse & pretty-print
      const parsed = JSON.parse(result);
      setRight(JSON.stringify(parsed, null, 2));
      setDirection('toJson');
    } catch (e) {
      setRight('# Error: ' + e.message);
    }
  }

  const ta = 'w-full px-3 py-2 bg-gray-950 border border-gray-800 text-xs text-gray-200 font-mono resize-none';

  return html`
  <div class="p-5 space-y-3">
    <div>
      <label class="block text-xs text-gray-500 mb-1">Input</label>
      <textarea class=${ta} rows="8" value=${left} onInput=${e => setLeft(e.target.value)}
        placeholder='Paste JSON or Elixir map...'></textarea>
    </div>
    <div class="flex gap-2">
      <button class="px-3 py-1.5 bg-violet-600 hover:bg-violet-700 text-white text-xs rounded cursor-pointer border-none"
        onClick=${convertToElixir}>JSON \u2192 Elixir Map</button>
      <button class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 text-gray-300 text-xs rounded cursor-pointer border-none"
        onClick=${convertToJson}>Elixir Map \u2192 JSON</button>
      ${right && html`
        <button class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 text-gray-300 text-xs rounded cursor-pointer border-none ml-auto"
          onClick=${() => navigator.clipboard.writeText(right)}>Copy</button>
      `}
    </div>
    ${right && html`
      <div>
        <label class="block text-xs text-gray-500 mb-1">${direction === 'toElixir' ? 'Elixir Map' : 'JSON'}</label>
        <pre class="bg-gray-950 border border-gray-800 p-3 text-xs font-mono whitespace-pre-wrap text-emerald-400 overflow-x-auto">${right}</pre>
      </div>
    `}
  </div>
  `;
}

/* ── Tool: JWT Token ── */
function ToolJwt() {
  const [mode, setMode] = useState('create'); // create | decode
  const [claims, setClaims] = useState('{\n  "user": "alice",\n  "app": "myapp",\n  "roles": ["admin"]\n}');
  const [token, setToken] = useState('');
  const [result, setResult] = useState(null);
  const [loading, setLoading] = useState(false);

  async function createToken() {
    setLoading(true);
    try {
      const parsed = JSON.parse(claims);
      const claimsStr = jsonToElixir(parsed);
      const code = 'Mooncore.Auth.Token.new_token(' + claimsStr + ')';
      const r = await api('/api/eval', { body: { code } });
      setResult(r);
      if (r.ok) {
        // Extract token string from {:ok, "token..."} result
        const m = r.result.match(/"([^"]+)"/);
        if (m) setToken(m[1]);
      }
    } catch (e) {
      setResult({ ok: false, error: 'Invalid JSON: ' + e.message });
    }
    setLoading(false);
  }

  async function decodeToken() {
    if (!token.trim()) return;
    setLoading(true);
    const code = 'Mooncore.Auth.Token.solve("' + token.trim().replace(/"/g, '\\"') + '")';
    const r = await api('/api/eval', { body: { code } });
    setResult(r);
    setLoading(false);
  }

  function decodePayload() {
    if (!token.trim()) return;
    try {
      const parts = token.trim().split('.');
      if (parts.length !== 3) { setResult({ ok: false, error: 'Invalid JWT format (expected 3 parts)' }); return; }
      const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
      // Check expiry
      if (payload.exp) {
        const now = Math.floor(Date.now() / 1000);
        payload._expired = payload.exp < now;
        payload._exp_human = new Date(payload.exp * 1000).toISOString();
      }
      if (payload.iat) payload._iat_human = new Date(payload.iat * 1000).toISOString();
      setResult({ ok: true, result: JSON.stringify(payload, null, 2) });
    } catch (e) {
      setResult({ ok: false, error: 'Failed to decode: ' + e.message });
    }
  }

  const ta = 'w-full px-3 py-2 bg-gray-950 border border-gray-800 text-xs text-gray-200 font-mono resize-none';

  return html`
  <div class="p-5 space-y-4">
    <div class="flex gap-2">
      <button class="px-3 py-1.5 text-xs rounded cursor-pointer border-none transition-colors
        ${mode === 'create' ? 'bg-violet-600 text-white' : 'bg-gray-800 text-gray-400 hover:text-gray-200'}"
        onClick=${() => setMode('create')}>Create Token</button>
      <button class="px-3 py-1.5 text-xs rounded cursor-pointer border-none transition-colors
        ${mode === 'decode' ? 'bg-violet-600 text-white' : 'bg-gray-800 text-gray-400 hover:text-gray-200'}"
        onClick=${() => setMode('decode')}>Decode Token</button>
    </div>

    ${mode === 'create' && html`
      <div class="space-y-3">
        <div>
          <label class="block text-xs text-gray-500 mb-1">Claims (JSON)</label>
          <textarea class=${ta} rows="6" value=${claims} onInput=${e => setClaims(e.target.value)}></textarea>
          <div class="text-xs text-gray-600 mt-1">Keys: user, app, tenant, scope, roles (list)</div>
        </div>
        <button class="px-4 py-1.5 bg-violet-600 hover:bg-violet-700 text-white text-xs rounded cursor-pointer border-none"
          onClick=${createToken} disabled=${loading}>
          ${loading ? html`<span class="spinner mr-1"></span>` : ''} Create
        </button>
        ${token && html`
          <div>
            <div class="flex items-center gap-2 mb-1">
              <label class="text-xs text-gray-500">Token</label>
              <button class="text-xs text-gray-600 hover:text-gray-300 bg-transparent border-none cursor-pointer"
                onClick=${() => navigator.clipboard.writeText(token)}>Copy</button>
            </div>
            <pre class="bg-gray-950 border border-gray-800 p-3 text-xs font-mono text-violet-400 break-all whitespace-pre-wrap">${token}</pre>
          </div>
        `}
      </div>
    `}

    ${mode === 'decode' && html`
      <div class="space-y-3">
        <div>
          <label class="block text-xs text-gray-500 mb-1">JWT Token</label>
          <textarea class=${ta} rows="4" value=${token} onInput=${e => setToken(e.target.value)}
            placeholder="eyJhbGciOiJSUzI1NiIs..."></textarea>
        </div>
        <div class="flex gap-2">
          <button class="px-3 py-1.5 bg-violet-600 hover:bg-violet-700 text-white text-xs rounded cursor-pointer border-none"
            onClick=${decodeToken} disabled=${loading}>
            ${loading ? html`<span class="spinner mr-1"></span>` : ''} Verify \u0026 Decode
          </button>
          <button class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 text-gray-300 text-xs rounded cursor-pointer border-none"
            onClick=${decodePayload}>Decode Payload (no verify)</button>
        </div>
      </div>
    `}

    ${result && html`
      <div class="border-t border-gray-800 pt-3">
        <div class="flex items-center gap-2 mb-1">
          <span class="text-xs font-semibold ${result.ok ? 'text-emerald-400' : 'text-red-400'}">
            ${result.ok ? '\u2713 Result' : '\u2717 Error'}
          </span>
          ${result.ok && html`
            <button class="text-xs text-gray-600 hover:text-gray-300 bg-transparent border-none cursor-pointer"
              onClick=${() => navigator.clipboard.writeText(result.result)}>Copy</button>
          `}
        </div>
        <pre class="bg-gray-950 border border-gray-800 p-3 text-xs font-mono whitespace-pre-wrap ${result.ok ? 'text-emerald-400' : 'text-red-400'}">${result.ok ? result.result : result.error}</pre>
      </div>
    `}
  </div>
  `;
}

/* ── Tool: Base64 ── */
function ToolBase64() {
  const [input, setInput] = useState('');
  const [output, setOutput] = useState('');

  function encode() { try { setOutput(btoa(input)); } catch (e) { setOutput('Error: ' + e.message); } }
  function decode() { try { setOutput(atob(input)); } catch (e) { setOutput('Error: ' + e.message); } }
  function encodeUrl() { try { setOutput(btoa(input).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')); } catch (e) { setOutput('Error: ' + e.message); } }
  function decodeUrl() { try { let s = input.replace(/-/g, '+').replace(/_/g, '/'); while (s.length % 4) s += '='; setOutput(atob(s)); } catch (e) { setOutput('Error: ' + e.message); } }

  const ta = 'w-full px-3 py-2 bg-gray-950 border border-gray-800 text-xs text-gray-200 font-mono resize-none';

  return html`
  <div class="p-5 space-y-3">
    <div>
      <label class="block text-xs text-gray-500 mb-1">Input</label>
      <textarea class=${ta} rows="5" value=${input} onInput=${e => setInput(e.target.value)}></textarea>
    </div>
    <div class="flex gap-2 flex-wrap">
      <button class="px-3 py-1.5 bg-violet-600 hover:bg-violet-700 text-white text-xs rounded cursor-pointer border-none" onClick=${encode}>Encode</button>
      <button class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 text-gray-300 text-xs rounded cursor-pointer border-none" onClick=${decode}>Decode</button>
      <button class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 text-gray-300 text-xs rounded cursor-pointer border-none" onClick=${encodeUrl}>URL-safe Encode</button>
      <button class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 text-gray-300 text-xs rounded cursor-pointer border-none" onClick=${decodeUrl}>URL-safe Decode</button>
      ${output && html`
        <button class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 text-gray-300 text-xs rounded cursor-pointer border-none ml-auto"
          onClick=${() => navigator.clipboard.writeText(output)}>Copy</button>
      `}
    </div>
    ${output && html`
      <div>
        <label class="block text-xs text-gray-500 mb-1">Output</label>
        <pre class="bg-gray-950 border border-gray-800 p-3 text-xs font-mono whitespace-pre-wrap text-emerald-400 break-all">${output}</pre>
      </div>
    `}
  </div>
  `;
}

/* ── Tool: Timestamps ── */
function ToolTimestamp() {
  const [unix, setUnix] = useState('');
  const [iso, setIso] = useState('');
  const [now, setNow] = useState(Math.floor(Date.now() / 1000));

  useEffect(() => { const t = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000); return () => clearInterval(t); }, []);

  function fromUnix() {
    const n = parseInt(unix, 10);
    if (isNaN(n)) { setIso('Invalid number'); return; }
    // Auto-detect seconds vs milliseconds
    const ts = n > 1e12 ? n : n * 1000;
    setIso(new Date(ts).toISOString());
  }
  function fromIso() {
    const d = new Date(iso);
    if (isNaN(d.getTime())) { setUnix('Invalid date'); return; }
    setUnix(String(Math.floor(d.getTime() / 1000)));
  }
  function setNowValues() { const n = Math.floor(Date.now() / 1000); setUnix(String(n)); setIso(new Date(n * 1000).toISOString()); }

  const ic = 'w-full px-3 py-2 bg-gray-950 border border-gray-800 text-xs text-gray-200 font-mono';

  return html`
  <div class="p-5 space-y-4">
    <div class="flex items-center gap-3">
      <span class="text-xs text-gray-500">Now:</span>
      <code class="text-xs text-violet-400">${now}</code>
      <span class="text-xs text-gray-600">(${new Date(now * 1000).toISOString()})</span>
      <button class="px-2 py-1 bg-gray-800 hover:bg-gray-700 text-gray-400 text-xs rounded cursor-pointer border-none"
        onClick=${setNowValues}>Use now</button>
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div>
        <label class="block text-xs text-gray-500 mb-1">Unix Timestamp</label>
        <input class=${ic} value=${unix} onInput=${e => setUnix(e.target.value)} placeholder="1711929600" />
        <button class="mt-1 px-3 py-1.5 bg-violet-600 hover:bg-violet-700 text-white text-xs rounded cursor-pointer border-none"
          onClick=${fromUnix}>\u2192 to ISO</button>
      </div>
      <div>
        <label class="block text-xs text-gray-500 mb-1">ISO 8601 / Date string</label>
        <input class=${ic} value=${iso} onInput=${e => setIso(e.target.value)} placeholder="2026-04-01T00:00:00Z" />
        <button class="mt-1 px-3 py-1.5 bg-violet-600 hover:bg-violet-700 text-white text-xs rounded cursor-pointer border-none"
          onClick=${fromIso}>\u2192 to Unix</button>
      </div>
    </div>
  </div>
  `;
}

/* ── Tool: Inspect (eval & inspect Elixir terms) ── */
function ToolInspect() {
  const [code, setCode] = useState('');
  const [result, setResult] = useState(null);
  const [loading, setLoading] = useState(false);

  async function inspect() {
    if (!code.trim()) return;
    setLoading(true);
    const wrapped = code.trim() + ' |> inspect(pretty: true, limit: :infinity)';
    const r = await api('/api/eval', { body: { code: wrapped } });
    setResult(r);
    setLoading(false);
  }

  async function typeOf() {
    if (!code.trim()) return;
    setLoading(true);
    const wrapped = 'val = ' + code.trim() + '\n[type: val.__struct__] rescue [type: "#{is_map(val) && "map" || is_list(val) && "list" || is_binary(val) && "binary" || is_integer(val) && "integer" || is_float(val) && "float" || is_atom(val) && "atom" || is_tuple(val) && "tuple" || is_pid(val) && "pid" || "other"}", byte_size: (is_binary(val) && byte_size(val)) || nil, length: (is_list(val) && length(val)) || (is_map(val) && map_size(val)) || nil] |> Enum.reject(fn {_, v} -> is_nil(v) end) |> inspect()';
    const r = await api('/api/eval', { body: { code: wrapped } });
    setResult(r);
    setLoading(false);
  }

  const ta = 'w-full px-3 py-2 bg-gray-950 border border-gray-800 text-xs text-gray-200 font-mono resize-none';

  return html`
  <div class="p-5 space-y-3">
    <div>
      <label class="block text-xs text-gray-500 mb-1">Elixir Expression</label>
      <textarea class=${ta} rows="4" value=${code} onInput=${e => setCode(e.target.value)}
        placeholder='%{hello: "world"} |> Map.keys()'></textarea>
    </div>
    <div class="flex gap-2">
      <button class="px-3 py-1.5 bg-violet-600 hover:bg-violet-700 text-white text-xs rounded cursor-pointer border-none"
        onClick=${inspect} disabled=${loading}>
        ${loading ? html`<span class="spinner mr-1"></span>` : ''} Inspect</button>
      <button class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 text-gray-300 text-xs rounded cursor-pointer border-none"
        onClick=${typeOf} disabled=${loading}>Type Info</button>
      ${result && result.ok && html`
        <button class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 text-gray-300 text-xs rounded cursor-pointer border-none ml-auto"
          onClick=${() => navigator.clipboard.writeText(result.result)}>Copy</button>
      `}
    </div>
    ${result && html`
      <div>
        <pre class="bg-gray-950 border border-gray-800 p-3 text-xs font-mono whitespace-pre-wrap ${result.ok ? 'text-emerald-400' : 'text-red-400'}">${result.ok ? result.result : result.error}</pre>
      </div>
    `}
  </div>
  `;
}

/* ─── Clients Page (connected sockets, rooms/channels, members) ─── */
