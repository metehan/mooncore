defmodule Mooncore.Dev.Page do
  @moduledoc false

  def render do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Mooncore Dev</title>
      <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
      <script src="https://cdn.jsdelivr.net/npm/preact@10.19.3/dist/preact.umd.js"></script>
      <script src="https://cdn.jsdelivr.net/npm/preact@10.19.3/hooks/dist/hooks.umd.js"></script>
      <script src="https://cdn.jsdelivr.net/npm/htm@3.1.1/dist/htm.umd.js"></script>
      <style>
        body { background: #1a1a2e; color: #e0e0e0; font-family: 'Segoe UI', system-ui, sans-serif; }
        .card { background: #16213e; border: 1px solid #0f3460; }
        .card-header { background: #0f3460; color: #e94560; font-weight: 600; }
        #console-output { background: #0d1117; color: #c9d1d9; font-family: 'JetBrains Mono', 'Fira Code', monospace;
          font-size: 13px; height: 300px; overflow-y: auto; padding: 12px; border-radius: 6px; white-space: pre-wrap; }
        #console-input { background: #0d1117; color: #c9d1d9; border: 1px solid #30363d;
          font-family: 'JetBrains Mono', 'Fira Code', monospace; font-size: 13px; }
        #console-input:focus { border-color: #e94560; box-shadow: 0 0 0 .2rem rgba(233,69,96,.25); color: #c9d1d9; background: #0d1117; }
        .log-entry { border-bottom: 1px solid #21262d; padding: 4px 0; font-size: 12px; }
        .log-tag { color: #e94560; font-weight: 600; }
        .log-time { color: #8b949e; }
        .btn-moon { background: #e94560; border: none; color: white; }
        .btn-moon:hover { background: #c73e54; color: white; }
        .btn-outline-moon { border-color: #e94560; color: #e94560; }
        .btn-outline-moon:hover { background: #e94560; color: white; }
        .action-item { cursor: pointer; padding: 6px 10px; border-radius: 4px; font-size: 13px; }
        .action-item:hover { background: #0f3460; }
        .badge-public { background: #238636; }
        .badge-auth { background: #e94560; }
        .nav-tabs .nav-link { color: #8b949e; border: none; }
        .nav-tabs .nav-link.active { color: #e94560; background: transparent; border-bottom: 2px solid #e94560; }
        pre { color: #c9d1d9; }
        .form-control, .form-select { background: #0d1117; color: #c9d1d9; border-color: #30363d; }
        .form-control:focus, .form-select:focus { background: #0d1117; color: #c9d1d9; border-color: #e94560; box-shadow: 0 0 0 .2rem rgba(233,69,96,.25); }
        .table { color: #c9d1d9; }
        .spinner { display: inline-block; width: 14px; height: 14px; border: 2px solid #e94560;
          border-top-color: transparent; border-radius: 50%; animation: spin .6s linear infinite; }
        @keyframes spin { to { transform: rotate(360deg); } }
      </style>
    </head>
    <body>
    <div id="app"></div>
    <script>
    const { h, render, Component } = preact;
    const { useState, useEffect, useRef, useCallback } = preactHooks;
    const html = htm.bind(h);

    const BASE = window.location.pathname.replace(/\\/$/, '');

    async function api(path, body) {
      const opts = body ? { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(body) }
                        : { method: 'GET' };
      const r = await fetch(BASE + path, opts);
      return r.json();
    }

    function App() {
      const [tab, setTab] = useState('actions');
      return html`
        <div class="container-fluid py-3">
          <div class="d-flex align-items-center mb-3">
            <h4 class="mb-0 me-3" style="color:#e94560">☾ Mooncore Dev</h4>
            <span class="text-muted small">Development Dashboard</span>
          </div>
          <ul class="nav nav-tabs mb-3">
            ${['actions','runner','logs','console','config'].map(t => html`
              <li class="nav-item">
                <a class="nav-link ${tab===t?'active':''}" href="#" onClick=${e=>{e.preventDefault();setTab(t)}}>
                  ${t.charAt(0).toUpperCase()+t.slice(1)}
                </a>
              </li>
            `)}
          </ul>
          ${tab==='actions' && html`<${ActionsTab} />`}
          ${tab==='runner' && html`<${RunnerTab} />`}
          ${tab==='logs' && html`<${LogsTab} />`}
          ${tab==='console' && html`<${ConsoleTab} />`}
          ${tab==='config' && html`<${ConfigTab} />`}
        </div>
      `;
    }

    function ActionsTab() {
      const [actions, setActions] = useState([]);
      const [loading, setLoading] = useState(true);
      useEffect(() => { api('/api/actions').then(d => { setActions(d.actions||[]); setLoading(false); }); }, []);
      if (loading) return html`<div class="spinner"></div>`;
      return html`
        <div class="card">
          <div class="card-header">Registered Actions (${actions.length})</div>
          <div class="card-body p-0">
            <table class="table table-sm mb-0">
              <thead><tr><th>Action</th><th>App</th><th>Handler</th><th>Access</th></tr></thead>
              <tbody>
                ${actions.map(a => html`
                  <tr class="action-item">
                    <td><code>${a.action}</code></td>
                    <td>${a.app}</td>
                    <td class="text-muted small">${a.handler}</td>
                    <td>${a.public ? html`<span class="badge badge-public">public</span>`
                                   : html`<span class="badge badge-auth">${(a.roles||[]).join(', ')}</span>`}</td>
                  </tr>
                `)}
              </tbody>
            </table>
          </div>
        </div>
      `;
    }

    function RunnerTab() {
      const [action, setAction] = useState('');
      const [params, setParams] = useState('{}');
      const [auth, setAuth] = useState('');
      const [result, setResult] = useState(null);
      const [loading, setLoading] = useState(false);

      async function run() {
        setLoading(true);
        let p = {}, a = null;
        try { p = JSON.parse(params); } catch(e) { setResult({error:'Invalid params JSON'}); setLoading(false); return; }
        if (auth.trim()) { try { a = JSON.parse(auth); } catch(e) { setResult({error:'Invalid auth JSON'}); setLoading(false); return; } }
        const r = await api('/api/action', { action, params: p, auth: a });
        setResult(r);
        setLoading(false);
      }

      return html`
        <div class="row">
          <div class="col-md-6">
            <div class="card">
              <div class="card-header">Run Action</div>
              <div class="card-body">
                <div class="mb-3">
                  <label class="form-label small">Action Name</label>
                  <input class="form-control" value=${action} onInput=${e=>setAction(e.target.value)} placeholder="task.create" />
                </div>
                <div class="mb-3">
                  <label class="form-label small">Params (JSON)</label>
                  <textarea class="form-control" rows="4" value=${params} onInput=${e=>setParams(e.target.value)}></textarea>
                </div>
                <div class="mb-3">
                  <label class="form-label small">Auth (JSON, optional)</label>
                  <textarea class="form-control" rows="3" value=${auth} onInput=${e=>setAuth(e.target.value)}
                    placeholder='{"roles":["user"],"user":"test","app":"myapp","dkey":"1","scope":"default"}'></textarea>
                </div>
                <button class="btn btn-moon" onClick=${run} disabled=${loading}>
                  ${loading ? html`<span class="spinner me-1"></span>` : ''} Run
                </button>
              </div>
            </div>
          </div>
          <div class="col-md-6">
            <div class="card">
              <div class="card-header">Result</div>
              <div class="card-body">
                <pre style="max-height:400px;overflow:auto">${result ? JSON.stringify(result, null, 2) : 'No result yet'}</pre>
              </div>
            </div>
          </div>
        </div>
      `;
    }

    function LogsTab() {
      const [logs, setLogs] = useState([]);
      const [tag, setTag] = useState('');
      const [auto, setAuto] = useState(false);
      const intervalRef = useRef(null);

      const fetchLogs = useCallback(async () => {
        const q = tag ? '?tag='+encodeURIComponent(tag) : '';
        const d = await api('/api/logs'+q);
        setLogs(d.logs || []);
      }, [tag]);

      useEffect(() => { fetchLogs(); }, [tag]);
      useEffect(() => {
        if (auto) { intervalRef.current = setInterval(fetchLogs, 2000); }
        else { clearInterval(intervalRef.current); }
        return () => clearInterval(intervalRef.current);
      }, [auto, fetchLogs]);

      async function clearLogs() {
        await api('/api/mcp', { tool: 'clear_logs' });
        setLogs([]);
      }

      return html`
        <div class="card">
          <div class="card-header d-flex justify-content-between align-items-center">
            <span>Logs (${logs.length})</span>
            <div class="d-flex gap-2 align-items-center">
              <input class="form-control form-control-sm" style="width:120px" placeholder="tag filter" value=${tag} onInput=${e=>setTag(e.target.value)} />
              <button class="btn btn-sm btn-outline-moon" onClick=${()=>setAuto(!auto)}>${auto?'Stop':'Auto'}</button>
              <button class="btn btn-sm btn-outline-moon" onClick=${fetchLogs}>Refresh</button>
              <button class="btn btn-sm btn-outline-moon" onClick=${clearLogs}>Clear</button>
            </div>
          </div>
          <div class="card-body p-0" style="max-height:500px;overflow-y:auto">
            ${logs.length === 0 ? html`<div class="p-3 text-muted">No logs. Enable lifecycle logging by passing mooncore_log: true in your action params.</div>` :
              logs.map(l => html`
                <div class="log-entry px-3">
                  <span class="log-tag">[${l.tag}]</span>
                  <span class="log-time ms-2">${new Date(l.timestamp).toLocaleTimeString()}</span>
                  <pre class="mb-0 mt-1" style="font-size:11px">${JSON.stringify(l.data, null, 2)}</pre>
                </div>
              `)
            }
          </div>
        </div>
      `;
    }

    function ConsoleTab() {
      const [history, setHistory] = useState([]);
      const [input, setInput] = useState('');
      const [cmdHistory, setCmdHistory] = useState([]);
      const [histIdx, setHistIdx] = useState(-1);
      const [loading, setLoading] = useState(false);
      const outputRef = useRef(null);

      async function exec() {
        if (!input.trim()) return;
        setLoading(true);
        const cmd = input;
        setCmdHistory(prev => [cmd, ...prev]);
        setHistIdx(-1);
        setHistory(prev => [...prev, { type: 'input', text: cmd }]);
        setInput('');
        const r = await api('/api/eval', { code: cmd });
        setHistory(prev => [...prev, { type: r.ok ? 'output' : 'error', text: r.ok ? r.result : r.error }]);
        setLoading(false);
        setTimeout(() => { if (outputRef.current) outputRef.current.scrollTop = outputRef.current.scrollHeight; }, 50);
      }

      function onKey(e) {
        if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); exec(); }
        if (e.key === 'ArrowUp') { e.preventDefault(); const ni = Math.min(histIdx+1, cmdHistory.length-1); setHistIdx(ni); setInput(cmdHistory[ni]||''); }
        if (e.key === 'ArrowDown') { e.preventDefault(); const ni = Math.max(histIdx-1, -1); setHistIdx(ni); setInput(ni===-1?'':cmdHistory[ni]||''); }
      }

      return html`
        <div class="card">
          <div class="card-header">IEx Console</div>
          <div class="card-body p-0">
            <div id="console-output" ref=${outputRef}>
              <div class="text-muted mb-2">Mooncore Interactive Elixir — evaluate code in the running application</div>
              ${history.map(h => html`
                <div style="color:${h.type==='input'?'#e94560':h.type==='error'?'#f85149':'#7ee787'}">
                  ${h.type==='input'?'iex> ':''}${h.text}
                </div>
              `)}
              ${loading && html`<div><span class="spinner"></span></div>`}
            </div>
            <div class="p-2 d-flex gap-2" style="border-top:1px solid #30363d">
              <span class="d-flex align-items-center" style="color:#e94560;font-family:monospace">iex></span>
              <input id="console-input" class="form-control" value=${input}
                onInput=${e=>setInput(e.target.value)} onKeyDown=${onKey}
                placeholder="Enum.map(1..5, & &1 * 2)" autocomplete="off" />
              <button class="btn btn-moon btn-sm" onClick=${exec} disabled=${loading}>Run</button>
            </div>
          </div>
        </div>
      `;
    }

    function ConfigTab() {
      const [config, setConfig] = useState(null);
      const [apps, setApps] = useState([]);
      useEffect(() => {
        api('/api/config').then(d => setConfig(d.config));
        api('/api/apps').then(d => setApps(d.apps || []));
      }, []);
      return html`
        <div class="row">
          <div class="col-md-6">
            <div class="card mb-3">
              <div class="card-header">Server Config</div>
              <div class="card-body">
                <pre>${config ? JSON.stringify(config, null, 2) : 'Loading...'}</pre>
              </div>
            </div>
          </div>
          <div class="col-md-6">
            <div class="card">
              <div class="card-header">Registered Apps (${apps.length})</div>
              <div class="card-body p-0">
                <table class="table table-sm mb-0">
                  <thead><tr><th>Key</th><th>Name</th><th>Roles</th><th>Action Module</th></tr></thead>
                  <tbody>
                    ${apps.map(a => html`
                      <tr>
                        <td><code>${a.key}</code></td>
                        <td>${a.name}</td>
                        <td class="small">${(a.roles||[]).join(', ')}</td>
                        <td class="small text-muted">${a.action_module}</td>
                      </tr>
                    `)}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      `;
    }

    render(html`<${App} />`, document.getElementById('app'));
    </script>
    </body>
    </html>
    """
  end
end
