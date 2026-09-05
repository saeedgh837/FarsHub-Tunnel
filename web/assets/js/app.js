/* ==========================================================================
   FarsHub Panel — application
   ========================================================================== */

import {
  LOCALES, t, locale, toggleLocale, applyDocumentLocale,
  num, pct, bytes, bitrate, duration, clock,
} from './i18n.js';
import { fetchStats } from './data.js';
import { sparkline, ring } from './sparkline.js';

const POLL_MS = 2000;
const SPARK_SAMPLES = 90;          // ≈ 3 دقیقه در فاصله‌ی 2 ثانیه

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
const slot = (name) => $$(`[data-slot="${name}"]`);

const history = {
  throughput: ring(SPARK_SAMPLES),
  latency: ring(SPARK_SAMPLES),
};

let lastGood = null;
let portFilter = '';

/* ------------------------------------------------------------------ helpers -- */

function setText(name, value) {
  for (const el of slot(name)) el.textContent = value;
}

/** مقدار + یکای مقیاس‌شده را در دو اسلات جدا می‌نویسد. */
function setScaled(name, scaled) {
  setText(name, scaled ? scaled.value : t('unit.none'));
  setText(`${name}-unit`, scaled ? scaled.unit : '');
}

function isRTL() {
  return document.documentElement.dir === 'rtl';
}

/** درصد → سطح هشدار برای رنگ‌بندی متر. */
function level(p) {
  if (p == null) return 'ok';
  if (p >= 90) return 'high';
  if (p >= 75) return 'warn';
  return 'ok';
}

/** نقش خام سرویس → 'server' | 'client' | 'unknown'. */
function sideOf(role) {
  const s = String(role ?? '').toLowerCase();
  if (/server|serve|remote|edge|kharej/.test(s)) return 'server';
  if (/client|local|iran|nat/.test(s)) return 'client';
  return 'unknown';
}

/* ------------------------------------------------------------------- i18n UI -- */

function applyTranslations() {
  applyDocumentLocale();

  for (const el of $$('[data-i18n]')) el.textContent = t(el.dataset.i18n);
  for (const el of $$('[data-i18n-placeholder]')) {
    el.placeholder = t(el.dataset.i18nPlaceholder);
  }

  // برچسب دکمه‌ی زبان همیشه زبان *بعدی* را نشان می‌دهد
  const codes = Object.keys(LOCALES);
  const next = codes[(codes.indexOf(locale()) + 1) % codes.length];
  const langBtn = $('#lang-btn');
  $('#lang-label').textContent = LOCALES[next].name;
  langBtn.setAttribute('aria-label', t('a11y.lang'));
  langBtn.setAttribute('lang', LOCALES[next].lang);

  const themeBtn = $('#theme-btn');
  themeBtn.setAttribute('aria-label', t('a11y.theme'));
  $('#theme-label').textContent = document.documentElement.dataset.theme === 'dark'
    ? (locale() === 'fa' ? 'روشن' : 'Light')
    : (locale() === 'fa' ? 'تیره' : 'Dark');

  $('.skip-link').textContent = t('a11y.skip');

  if (lastGood) render(lastGood);   // اعداد را با ارقام زبان جدید بازنویسی کن
}

/* -------------------------------------------------------------------- theme -- */

function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  try { localStorage.setItem('farshub.theme', theme); } catch { /* ignore */ }
  $('[data-icon-dark]').hidden = theme !== 'dark';
  $('[data-icon-light]').hidden = theme === 'dark';
  $('#theme-label').textContent = theme === 'dark'
    ? (locale() === 'fa' ? 'روشن' : 'Light')
    : (locale() === 'fa' ? 'تیره' : 'Dark');
}

/* --------------------------------------------------------------- feed status -- */

function setFeed(state) {
  const feed = $('#feed');
  feed.dataset.state = state;
  $('[data-feed-label]', feed).textContent = t(`meta.${state}`);
}

/* -------------------------------------------------------------- hero / wire -- */

function renderHero(d) {
  const link = $('#link');
  link.dataset.state = d.state;
  setText('state', t(`state.${d.state}`));

  const tx = d.txRate ?? 0;
  const rx = d.rxRate ?? 0;
  const total = (d.txRate == null && d.rxRate == null) ? null : tx + rx;

  setScaled('throughput', total == null ? null : bitrate(total));
  setScaled('tx', d.txRate == null ? null : bitrate(tx));
  setScaled('rx', d.rxRate == null ? null : bitrate(rx));

  setText('transport', d.transport ?? t('unit.none'));
  setText('latency-chip', d.latency == null
    ? t('unit.none')
    : `${num(Math.round(d.latency))} ${t('unit.ms')}`);

  // سرعت انیمیشن ریل از گذردهی واقعی مشتق می‌شود: بیشتر → سریع‌تر.
  // مقیاس لگاریتمی، چون گذردهی چند مرتبه‌ی بزرگی تغییر می‌کند.
  tuneRail($('[data-rail="up"]'), d.txRate);
  tuneRail($('[data-rail="down"]'), d.rxRate);

  renderSide(d);
}

/** کدام سمت تونل همین دستگاه است — چیپ کنار وضعیت + نشانه روی گره. */
function renderSide(d) {
  const side = sideOf(d.role);
  const chip = $('.link__side');

  if (chip) {
    chip.dataset.side = side;
    chip.title = t(`role.hint.${side}`);
    $('[data-slot="side"]', chip).textContent = t(`role.self.${side}`);
  }

  for (const node of $$('.node')) {
    node.dataset.here = String(node.dataset.node === side);
  }

  const dot = $('[data-slot-side-dot]');
  if (dot) dot.dataset.side = side;
}

function tuneRail(rail, bps) {
  if (!rail) return;
  const idle = !bps || bps < 1024;
  rail.dataset.idle = String(idle);
  if (idle) return;
  const mbps = bps / 1e6;
  const secs = Math.min(4, Math.max(0.35, 2.4 / (1 + Math.log10(1 + mbps * 9))));
  rail.style.setProperty('--speed', `${secs.toFixed(2)}s`);
}

/* ---------------------------------------------------------------- KPI tiles -- */

function renderTiles(d) {
  const total = (d.txRate == null && d.rxRate == null)
    ? null
    : (d.txRate ?? 0) + (d.rxRate ?? 0);

  setScaled('k-throughput', total == null ? null : bitrate(total));
  setText('k-conns', d.conns == null ? t('unit.none') : num(d.conns));
  setText('k-latency', d.latency == null ? t('unit.none') : num(Math.round(d.latency)));
  setScaled('k-total', bytes(d.totalTraffic ?? ((d.totalUp ?? 0) + (d.totalDown ?? 0))));

  if (total != null) history.throughput.push(total);
  if (d.latency != null) history.latency.push(d.latency);

  const rtl = isRTL();
  sparkline($('[data-spark="throughput"]'), history.throughput.values(), { rtl });
  sparkline($('[data-spark="latency"]'), history.latency.values(), { rtl });

  for (const svg of $$('.tile__spark')) {
    svg.setAttribute('aria-label', t('a11y.sparkline'));
  }
}

/* --------------------------------------------------------------- ports table -- */

function renderPorts(d) {
  const wrap = $('#ports-wrap');
  const q = portFilter.trim().toLowerCase();

  const rows = d.ports.filter((p) => !q
    || String(p.port).toLowerCase().includes(q)
    || String(p.target ?? '').toLowerCase().includes(q));

  if (!rows.length) {
    // دو حالت متفاوت: هیچ پورتی وجود ندارد، یا جست‌وجو چیزی پیدا نکرد.
    wrap.replaceChildren(d.ports.length
      ? emptyState(t('ports.nomatch.title'), t('ports.nomatch.body'))
      : emptyState(t('ports.empty.title'), t('ports.empty.body')));
    return;
  }

  const maxTotal = Math.max(...rows.map((p) => p.up + p.down), 1);
  const sums = rows.reduce((a, p) => ({
    conns: a.conns + (p.conns ?? 0),
    up: a.up + p.up,
    down: a.down + p.down,
  }), { conns: 0, up: 0, down: 0 });

  const table = document.createElement('table');
  table.innerHTML = `
    <thead>
      <tr>
        <th scope="col">${t('ports.col.port')}</th>
        <th scope="col">${t('ports.col.target')}</th>
        <th scope="col" class="cell-num">${t('ports.col.conns')}</th>
        <th scope="col" class="cell-num">${t('ports.col.up')}</th>
        <th scope="col" class="cell-num">${t('ports.col.down')}</th>
        <th scope="col" class="cell-num">${t('ports.col.rate')}</th>
        <th scope="col">${t('ports.col.share')}</th>
      </tr>
    </thead>
    <tbody></tbody>
    <tfoot>
      <tr>
        <td colspan="2">${t('ports.total')}</td>
        <td class="cell-num num">${num(sums.conns)}</td>
        <td class="cell-num num">${fmtBytes(sums.up)}</td>
        <td class="cell-num num">${fmtBytes(sums.down)}</td>
        <td class="cell-num">—</td>
        <td></td>
      </tr>
    </tfoot>`;

  const tbody = $('tbody', table);
  for (const p of rows) {
    const share = ((p.up + p.down) / maxTotal) * 100;
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td><span class="port-chip">${escapeHTML(String(p.port))}</span></td>
      <td class="mono">${escapeHTML(p.target ?? t('unit.none'))}</td>
      <td class="cell-num num">${p.conns == null ? t('unit.none') : num(p.conns)}</td>
      <td class="cell-num num">${fmtBytes(p.up)}</td>
      <td class="cell-num num">${fmtBytes(p.down)}</td>
      <td class="cell-num num">${p.rate == null ? t('unit.none') : fmtRate(p.rate)}</td>
      <td>
        <span class="share">
          <span class="share__track">
            <span class="share__fill" style="inline-size:${share.toFixed(1)}%"></span>
          </span>
          <span class="share__pct num">${pct(share)}</span>
        </span>
      </td>`;
    tbody.append(tr);
  }

  wrap.replaceChildren(table);
}

function fmtBytes(v) {
  const s = bytes(v);
  return `${s.value} ${s.unit}`;
}

function fmtRate(v) {
  const s = bitrate(v);
  return `${s.value} ${s.unit}`;
}

function escapeHTML(s) {
  return String(s).replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}

function emptyState(title, body) {
  const el = document.createElement('div');
  el.className = 'empty';
  el.innerHTML = `
    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <rect x="3" y="5" width="18" height="14" rx="2" stroke="currentColor" stroke-width="1.6"/>
      <path d="M3 10h18" stroke="currentColor" stroke-width="1.6"/>
    </svg>
    <p class="empty__title">${escapeHTML(title)}</p>
    ${body ? `<p>${escapeHTML(body)}</p>` : ''}`;
  return el;
}

/* -------------------------------------------------------------------- meters -- */

function renderMeters(d) {
  const defs = [
    { key: 'sys.cpu', pct: d.cpu },
    { key: 'sys.ram', pct: d.ram, used: d.ramUsed, total: d.ramTotal },
    { key: 'sys.disk', pct: d.disk, used: d.diskUsed, total: d.diskTotal },
    { key: 'sys.swap', pct: d.swap, used: d.swapUsed },
  ];

  const frag = document.createDocumentFragment();

  for (const m of defs) {
    const el = document.createElement('div');
    el.className = 'meter';
    el.dataset.level = level(m.pct);

    const value = m.pct == null ? 0 : Math.min(100, Math.max(0, m.pct));

    /* موتور فقط برای CPU درصد می‌دهد؛ حافظه/دیسک/سواپ مقدار مطلق‌اند و بدون
       «کل»، درصدی وجود ندارد. در آن حالت به‌جای درصد، خود حجم را نشان می‌دهیم
       تا خانه‌ی متر خالی نماند. */
    const head = m.pct != null ? pct(m.pct)
      : m.used != null ? fmtBytes(m.used)
      : t('unit.none');
    const detail = (m.used != null && m.total != null)
      ? `${fmtBytes(m.used)} ${t('sys.of')} ${fmtBytes(m.total)}`
      : '';

    el.innerHTML = `
      <div class="meter__head">
        <span class="meter__name">${escapeHTML(t(m.key))}</span>
        <span class="meter__pct num">${escapeHTML(head)}</span>
      </div>
      <div class="meter__track" role="meter" aria-valuemin="0" aria-valuemax="100"
           aria-valuenow="${m.pct == null ? '' : value.toFixed(0)}"
           aria-label="${escapeHTML(t(m.key))}">
        <span class="meter__fill" style="inline-size:${value.toFixed(1)}%"></span>
      </div>
      ${detail ? `<p class="meter__detail num">${escapeHTML(detail)}</p>` : ''}`;

    frag.append(el);
  }

  $('#meters').replaceChildren(frag);
}

/* -------------------------------------------------------------------- events -- */

function renderEvents(d) {
  const host = $('#events');

  if (!d.events.length) {
    host.replaceChildren(emptyState(t('log.empty'), ''));
    return;
  }

  const frag = document.createDocumentFragment();

  for (const e of d.events.slice(0, 40)) {
    const lvl = ['info', 'warn', 'error'].includes(e.level) ? e.level : 'info';
    const el = document.createElement('div');
    el.className = 'event';
    el.dataset.level = lvl;
    const stamp = e.time ? clock(new Date(e.time)) : '';
    el.innerHTML = `
      <time class="event__time num">${escapeHTML(stamp)}</time>
      <span class="event__level">${escapeHTML(t(`log.level.${lvl}`))}</span>
      <span class="event__text">${escapeHTML(e.text)}</span>`;
    frag.append(el);
  }

  host.replaceChildren(frag);
}

/* -------------------------------------------------------- ribbon + specs -- */

function renderRibbon(d) {
  const side = sideOf(d.role);
  setText('m-role', side === 'unknown' ? (d.role ?? t('unit.none')) : t(`role.${side}`));
  setText('m-transport', d.transport ?? t('unit.none'));
  setText('m-uptime', d.uptime == null ? t('unit.none') : duration(d.uptime));
  setText('m-goroutines', d.goroutines == null ? t('unit.none') : num(d.goroutines));
  setText('m-version', d.version ?? t('unit.none'));
  setText('m-updated', clock());
}

/** برچسب، مقدار، و اینکه ارزش رونوشت‌گرفتن دارد یا نه. */
function specRows(d) {
  const h = d.host || {};
  const gb = (v) => (v == null ? null : fmtBytes(v));

  return [
    { key: 'srv.host', value: h.name, copy: true, mono: true },
    { key: 'srv.ip', value: h.ip, copy: true, mono: true },
    { key: 'srv.bind', value: h.bind, copy: true, mono: true },
    { key: 'srv.location', value: h.location },
    { key: 'srv.os', value: h.os },
    { key: 'srv.kernel', value: h.kernel, mono: true },
    { key: 'srv.arch', value: h.arch, mono: true },
    { key: 'srv.cores', value: h.cores == null ? null : num(h.cores), num: true },
    { key: 'srv.ram', value: gb(d.ramTotal), num: true },
    { key: 'srv.disk', value: gb(d.diskTotal), num: true },
    { key: 'srv.version', value: d.version, mono: true },
    { key: 'srv.boot', value: h.boot == null ? null : duration(h.boot) },
  ];
}

const COPY_ICON = `<svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
  <rect x="9" y="9" width="11" height="11" rx="2" stroke="currentColor" stroke-width="1.8"/>
  <path d="M15 5.5A1.5 1.5 0 0 0 13.5 4h-8A1.5 1.5 0 0 0 4 5.5v8A1.5 1.5 0 0 0 5.5 15"
        stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
</svg>`;

function renderSpecs(d) {
  const host = $('#specs');
  const frag = document.createDocumentFragment();

  for (const row of specRows(d)) {
    // فیلدهایی که سرویس نفرستاده حذف می‌شوند، نه اینکه ردیف «—» بسازند
    if (row.value == null || row.value === '') continue;

    const el = document.createElement('div');
    el.className = 'specs__row';
    const cls = row.mono ? 'mono' : (row.num ? 'num' : '');
    el.innerHTML = `
      <dt>${escapeHTML(t(row.key))}</dt>
      <dd><span class="${cls}">${escapeHTML(String(row.value))}</span>${
        row.copy
          ? `<button class="specs__copy" type="button" aria-label="${escapeHTML(t('srv.copy'))}"
                     data-copy="${escapeHTML(String(row.value))}">${COPY_ICON}</button>`
          : ''
      }</dd>`;
    frag.append(el);
  }

  if (!frag.childElementCount) {
    host.replaceChildren(emptyState(t('srv.title'), t('srv.empty')));
    return;
  }

  host.replaceChildren(frag);
}

function render(d) {
  renderHero(d);
  renderRibbon(d);
  renderTiles(d);
  renderPorts(d);
  renderMeters(d);
  renderEvents(d);
  renderSpecs(d);
}

/* --------------------------------------------------------------------- poll -- */

let timer = null;
let failures = 0;

async function tick() {
  try {
    const d = await fetchStats();
    lastGood = d;
    failures = 0;
    setFeed('live');
    render(d);
  } catch {
    failures += 1;
    // یک شکست ممکن است گذرا باشد؛ بعد از دو شکست پیاپی حالت offline
    setFeed(failures >= 2 ? 'offline' : 'stale');
    if (lastGood) renderHero({ ...lastGood, state: failures >= 2 ? 'unknown' : lastGood.state });
  }
}

function startPolling() {
  stopPolling();
  tick();
  timer = setInterval(tick, POLL_MS);
}

function stopPolling() {
  if (timer) { clearInterval(timer); timer = null; }
}

/* --------------------------------------------------------------------- boot -- */

function boot() {
  applyTheme(document.documentElement.dataset.theme || 'dark');
  applyTranslations();

  $('#lang-btn').addEventListener('click', () => {
    toggleLocale();
    applyTranslations();
  });

  $('#theme-btn').addEventListener('click', () => {
    applyTheme(document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark');
  });

  const search = $('#port-search');
  search.addEventListener('input', () => {
    portFilter = search.value;
    if (lastGood) renderPorts(lastGood);
  });

  // رونوشت مشخصات — delegation، چون سطرها هر ۲ ثانیه بازساخته می‌شوند
  $('#specs').addEventListener('click', async (ev) => {
    const btn = ev.target.closest('.specs__copy');
    if (!btn) return;
    try {
      await navigator.clipboard.writeText(btn.dataset.copy);
      btn.dataset.done = 'true';
      btn.setAttribute('aria-label', t('srv.copied'));
      setTimeout(() => {
        delete btn.dataset.done;
        btn.setAttribute('aria-label', t('srv.copy'));
      }, 1200);
    } catch { /* clipboard در http بدون localhost بلاک است — بی‌صدا رد شو */ }
  });

  // وقتی تب پنهان است، درخواستی نمی‌فرستیم
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      stopPolling();
      setFeed('paused');
    } else {
      startPolling();
    }
  });

  startPolling();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', boot, { once: true });
} else {
  boot();
}
