function SectionHeader({ title, count, actions }) {
  return html`
<div class="px-5 py-3 border-b border-gray-800 flex items-center justify-between bg-gray-900/50">
  <div class="flex items-center gap-2">
    <span class="text-xs font-semibold text-gray-400 uppercase tracking-wider">${title}</span>
    ${count != null && html`<span class="text-xs bg-gray-800 text-gray-500 px-1.5 py-0.5 rounded-full">${count}</span>`}
  </div>
  ${actions}
</div>
  `;
}

/* ─── Dashboard Page ─── */
function fmtBytes(b) {
  if (b == null) return '0 B';
  if (b < 1024) return b + ' B';
  if (b < 1024 * 1024) return (b / 1024).toFixed(1) + ' KB';
  if (b < 1024 * 1024 * 1024) return (b / 1024 / 1024).toFixed(1) + ' MB';
  return (b / 1024 / 1024 / 1024).toFixed(2) + ' GB';
}

function fmtNum(n) {
  if (n == null) return '0';
  if (n >= 1e9) return (n / 1e9).toFixed(2) + 'B';
  if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M';
  if (n >= 1e3) return (n / 1e3).toFixed(1) + 'K';
  return String(n);
}

function fmtUptime(ms) {
  const s = Math.floor(ms / 1000);
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d > 0) return d + 'd ' + h + 'h ' + m + 'm';
  if (h > 0) return h + 'h ' + m + 'm';
  return m + 'm ' + (s % 60) + 's';
}

/* Sparkline SVG — small inline chart */
function Sparkline({ data, width = 120, height = 32, color = '#7c3aed' }) {
  if (!data || data.length < 2) return html`<div style="width:${width}px;height:${height}px"></div> `;
  const max = Math.max(...data, 1);
  const min = Math.min(...data);
  const range = max - min || 1;
  const pts = data.map((v, i) => {
    const x = (i / (data.length - 1)) * width;
    const y = height - ((v - min) / range) * (height - 4) - 2;
    return x + ',' + y;
  }).join(' ');
  const fillPts = pts + ' ' + width + ',' + height + ' 0,' + height;
  return html`
  <svg width=${width} height=${height} class="block">
    <polyline points=${fillPts} fill=${color} fill-opacity="0.1" stroke="none"/>
    <polyline points=${pts} fill="none" stroke=${color} stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
  </svg>
  `;
}

/* Horizontal bar gauge */
function Gauge({ value, max, label, used, color = '#7c3aed', warn = 0.8 }) {
  const pct = max ? Math.min(value / max, 1) : 0;
  const c = pct > warn ? '#f87171' : pct > warn * 0.8 ? '#fbbf24' : color;
  return html`
  <div class="space-y-1">
    <div class="flex justify-between text-xs">
      <span class="text-gray-400">${label}</span>
      <span class="text-gray-500">${used || fmtNum(value)} / ${fmtNum(max)} <span class="text-gray-600">(${(pct * 100).toFixed(1)}%)</span></span>
    </div>
    <div class="h-2 bg-gray-800 rounded-full overflow-hidden">
      <div class="h-full rounded-full transition-all duration-500" style="width:${pct * 100}%;background:${c}"></div>
    </div>
  </div>
  `;
}

/* Memory bar (horizontal, labeled) */
function MemBar({ label, bytes, total, color }) {
  const pct = total ? (bytes / total * 100) : 0;
  return html`
  <div class="flex items-center gap-3 py-1">
    <span class="text-xs text-gray-500 w-20 shrink-0">${label}</span>
    <div class="flex-1 h-3 bg-gray-800 rounded-full overflow-hidden">
      <div class="h-full rounded-full transition-all duration-500" style="width:${Math.max(pct, 0.5)}%;background:${color}"></div>
    </div>
    <span class="text-xs text-gray-400 w-20 text-right shrink-0">${fmtBytes(bytes)}</span>
  </div>
  `;
}

