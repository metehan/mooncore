const { h, render } = preact;
const { useState, useEffect, useRef, useCallback, useMemo } = preactHooks;
const html = htm.bind(h);

const BASE = window.location.pathname.replace(/\/$/, '');

async function api(path, opts) {
  const o = opts || {};
  const fetchOpts = o.body
    ? { method: o.method || 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(o.body) }
    : { method: o.method || 'GET' };
  const r = await fetch(BASE + path, fetchOpts);
  return r.json();
}

function destroyCodeMirror(instance) {
  if (!instance) return null;
  const wrapper = instance.getWrapperElement ? instance.getWrapperElement() : null;
  if (wrapper && wrapper.parentNode) wrapper.parentNode.removeChild(wrapper);
  return null;
}

/* ─── Menu items ─── */
const ICONS = {
  dashboard: html`<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/></svg>`,
  api: html`<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>`,
  tools: html`<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/></svg>`,
  guides: html`<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg>`,
  clients: html`<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>`,
  console: html`<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>`,
  files: html`<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>`,
  ets: html`<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"/><path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/></svg>`,
  sockets: html`<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/></svg>`,
};

/* ─── Moon Canvas component ─── */
/* size: pixel size (default 28). The canvas draws the animated moon and can serve
   as logo or inline spinner. Mounts via useEffect to avoid SSR issues. */
function MoonCanvas({ size = 28 }) {
  const canvasRef = useRef(null);
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const s = size * (window.devicePixelRatio || 1);
    canvas.width = s; canvas.height = s;
    const cx = s / 2, cy = s / 2, R = s / 2 * 0.87;

    const off = document.createElement('canvas');
    off.width = s; off.height = s;
    const oc = off.getContext('2d');

    function seededRand(seed) {
      let n = seed;
      return () => { n = (n * 1664525 + 1013904223) & 0xffffffff; return (n >>> 0) / 0xffffffff; };
    }

    (function drawSurface() {
      const g = oc.createRadialGradient(cx - R * 0.19, cy - R * 0.19, R * 0.08, cx, cy, R);
      g.addColorStop(0, '#e8e8e8'); g.addColorStop(0.3, '#d0d0d0');
      g.addColorStop(0.6, '#b0b0b0'); g.addColorStop(0.85, '#989898'); g.addColorStop(1, '#787878');
      oc.beginPath(); oc.arc(cx, cy, R, 0, Math.PI * 2); oc.fillStyle = g; oc.fill();

      const sc = R / 52;
      [
        { x: 48, y: 44, rx: 14, ry: 11, a: -0.3, dark: 0.22 },
        { x: 66, y: 58, rx: 10, ry: 8, a: 0.5, dark: 0.18 },
        { x: 38, y: 62, rx: 8, ry: 6, a: 0.2, dark: 0.16 },
        { x: 72, y: 38, rx: 6, ry: 5, a: -0.1, dark: 0.14 },
      ].forEach(m => {
        oc.save(); oc.translate((m.x - 60) * sc + cx, (m.y - 60) * sc + cy); oc.rotate(m.a);
        const mg = oc.createRadialGradient(0, 0, 1, 0, 0, Math.max(m.rx, m.ry) * sc);
        mg.addColorStop(0, `rgba(40,40,40,${m.dark})`); mg.addColorStop(0.7, `rgba(40,40,40,${m.dark * 0.5})`); mg.addColorStop(1, 'rgba(40,40,40,0)');
        oc.beginPath(); oc.ellipse(0, 0, m.rx * sc, m.ry * sc, 0, 0, Math.PI * 2); oc.fillStyle = mg; oc.fill(); oc.restore();
      });

      oc.save(); oc.globalCompositeOperation = 'destination-in';
      oc.beginPath(); oc.arc(cx, cy, R, 0, Math.PI * 2); oc.fillStyle = '#fff'; oc.fill(); oc.restore();

      [
        { x: 44, y: 40, r: 8 }, { x: 70, y: 52, r: 5.5 }, { x: 54, y: 70, r: 10 },
        { x: 36, y: 65, r: 4.5 }, { x: 76, y: 36, r: 4 }, { x: 60, y: 28, r: 3.5 },
        { x: 50, y: 55, r: 3 }, { x: 64, y: 75, r: 3 }, { x: 32, y: 48, r: 2.5 },
        { x: 80, y: 62, r: 2.5 }, { x: 46, y: 80, r: 2 }, { x: 72, y: 72, r: 2 },
      ].forEach(c => {
        const cr = c.r * sc;
        const cx2 = (c.x - 60) * sc + cx, cy2 = (c.y - 60) * sc + cy;
        const eb = oc.createRadialGradient(cx2, cy2, cr * 0.8, cx2, cy2, cr * 1.8);
        eb.addColorStop(0, 'rgba(210,210,210,0.25)'); eb.addColorStop(0.5, 'rgba(200,200,200,0.1)'); eb.addColorStop(1, 'rgba(200,200,200,0)');
        oc.beginPath(); oc.arc(cx2, cy2, cr * 1.8, 0, Math.PI * 2); oc.fillStyle = eb; oc.fill();
        const rim = oc.createRadialGradient(cx2 - cr * 0.3, cy2 - cr * 0.3, cr * 0.5, cx2, cy2, cr * 1.05);
        rim.addColorStop(0, 'rgba(255,255,255,0)'); rim.addColorStop(0.75, 'rgba(255,255,255,0.18)'); rim.addColorStop(1, 'rgba(255,255,255,0.08)');
        oc.beginPath(); oc.arc(cx2, cy2, cr * 1.05, 0, Math.PI * 2); oc.fillStyle = rim; oc.fill();
        const bowl = oc.createRadialGradient(cx2 + cr * 0.2, cy2 + cr * 0.2, 0, cx2, cy2, cr);
        bowl.addColorStop(0, 'rgba(30,30,30,0.55)'); bowl.addColorStop(0.6, 'rgba(30,30,30,0.4)'); bowl.addColorStop(1, 'rgba(30,30,30,0.05)');
        oc.beginPath(); oc.arc(cx2, cy2, cr, 0, Math.PI * 2); oc.fillStyle = bowl; oc.fill();
      });

      const rnd2 = seededRand(99);
      for (let i = 0; i < 320; i++) {
        const angle = rnd2() * Math.PI * 2, dist = rnd2() * R * 0.95;
        const nx = cx + Math.cos(angle) * dist, ny = cy + Math.sin(angle) * dist;
        const sz = rnd2() * 1.2 * sc + 0.3 * sc, bright = rnd2() > 0.5;
        oc.beginPath(); oc.arc(nx, ny, sz, 0, Math.PI * 2);
        oc.fillStyle = bright ? `rgba(255,255,255,${0.06 + rnd2() * 0.08})` : `rgba(0,0,0,${0.04 + rnd2() * 0.07})`;
        oc.fill();
      }

      const limb = oc.createRadialGradient(cx, cy, R * 0.55, cx, cy, R);
      limb.addColorStop(0, 'rgba(0,0,0,0)'); limb.addColorStop(0.7, 'rgba(0,0,0,0.05)'); limb.addColorStop(1, 'rgba(0,0,0,0.35)');
      oc.beginPath(); oc.arc(cx, cy, R, 0, Math.PI * 2); oc.fillStyle = limb; oc.fill();
    })();

    let start = null, rafId;
    function draw(t) {
      ctx.clearRect(0, 0, s, s);
      ctx.drawImage(off, 0, 0);
      const shadowR = R * 1.3, travel = R * 4.5;
      const sx = cx + R * 1.8 - t * travel, sy = cy - R * 1.8 + t * travel;
      ctx.save(); ctx.beginPath(); ctx.arc(cx, cy, R, 0, Math.PI * 2); ctx.clip();
      ctx.beginPath(); ctx.arc(sx, sy, shadowR, 0, Math.PI * 2); ctx.fillStyle = 'rgba(5,4,14,0.94)'; ctx.fill(); ctx.restore();
      const halo = ctx.createRadialGradient(cx, cy, R - 1, cx, cy, R + R * 0.13);
      halo.addColorStop(0, 'rgba(200,200,210,0.13)'); halo.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.beginPath(); ctx.arc(cx, cy, R + R * 0.13, 0, Math.PI * 2); ctx.fillStyle = halo; ctx.fill();
    }
    function animate(ts) { if (!start) start = ts; draw(((ts - start) % 8000) / 8000); rafId = requestAnimationFrame(animate); }
    rafId = requestAnimationFrame(animate);
    return () => cancelAnimationFrame(rafId);
  }, [size]);

  return html`<canvas ref=${canvasRef} style=${{ width: size + 'px', height: size + 'px', borderRadius: '50%', display: 'block' }} />`;
}

const MENU = [
  { id: 'dashboard', label: 'Dashboard' },
  { id: 'ets', label: 'ETS' },
  { id: 'api', label: 'Actions' },
  { id: 'console', label: 'Console' },
  { id: 'clients', label: 'Clients' },
  { id: 'sockets', label: 'Sockets' },
  { id: 'files', label: 'Files' },
  { id: 'guides', label: 'Guides' },
  { id: 'tools', label: 'Tools' }
];

