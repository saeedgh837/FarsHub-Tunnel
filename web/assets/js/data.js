/* ==========================================================================
   FarsHub Panel — data adapter
   موتور دو اندپوینت دارد و محتوایشان یکی نیست:
     /stats  آمار تونل و منابع سیستم (یک شیء تخت، کلیدها camelCase)
     /data   با sniffer=true آرایه‌ی مصرف هر پورت؛ در غیر این صورت HTML موتور
   و یک منبع سوم که موتور نیست:
     panel.json  فایل ایستا کنار پنل، برای چیزهایی که موتور هرگز نمی‌گوید:
                 نقش (server/client)، نسخه، مشخصات میزبان. اختیاری است.
   شکل دقیق پاسخ نسخه‌به‌نسخه متفاوت است، پس اینجا با چند نام محتمل برای هر
   فیلد کار می‌کنیم و هر چه پیدا نشد null می‌ماند (پنل «—» نشان می‌دهد، عدد
   جعلی نمی‌سازد).
   ========================================================================== */

/** اولین کلید موجود از میان چند نام محتمل. */
function pick(obj, names, fallback = null) {
  if (!obj) return fallback;
  for (const n of names) {
    const v = n.split('.').reduce((o, k) => (o == null ? o : o[k]), obj);
    if (v != null && v !== '') return v;
  }
  return fallback;
}

/* پیشوندهای حجم. موتور برچسب SI می‌زند ("GB") ولی پایه‌ی ۱۰۲۴ حساب می‌کند —
   روی سرور تأیید شد: برای ۲٫۱۴ GiB واقعیِ دیسک رشته‌ی "2.14 GB" می‌دهد. */
const BYTE_SCALE = { b: 1, k: 1024, m: 1024 ** 2, g: 1024 ** 3, t: 1024 ** 4, p: 1024 ** 5 };

function toNum(v) {
  if (v == null || typeof v === 'object' || typeof v === 'boolean') return null;
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  if (typeof v !== 'string') return null;

  // مقادیر موتور از پیش فرمت‌شده‌اند: "186.45 MB"، "2.09 KB/s"، "0 B".
  // بدون این، parseFloat واحد را دور می‌ریخت و "2.09 KB/s" عدد ۲٫۰۹ می‌شد.
  const m = /^(-?\d+(?:\.\d+)?)\s*([kmgtp])?i?b(?:\/s(?:ec)?)?$/i.exec(v.trim());
  if (m) {
    const n = parseFloat(m[1]);
    return Number.isFinite(n) ? n * BYTE_SCALE[(m[2] || 'b').toLowerCase()] : null;
  }

  // بقیه: "6.93%" → 6.93، "82" → 82، "Not running" → null
  const n = parseFloat(v.replace(/[^\d.-]/g, ''));
  return Number.isFinite(n) ? n : null;
}

/**
 * مثل pick، اما نام‌هایی که مقدارشان عدد نیست را رد می‌کند.
 * لازم است چون بعضی پاسخ‌ها هم‌نام دارند با شکل متفاوت: مثلاً `disk` یک شیء
 * {used,total} است و `disk_percent` عدد؛ pick ساده روی شیء متوقف می‌شد.
 */
function pickNum(obj, names) {
  if (!obj) return null;
  for (const n of names) {
    const v = toNum(n.split('.').reduce((o, k) => (o == null ? o : o[k]), obj));
    if (v != null) return v;
  }
  return null;
}

/**
 * پاسخ خام سرویس → شکل واحدی که رندرها مصرف می‌کنند.
 * portsRaw: آرایه‌ی مصرف پورت‌ها، از اندپوینت جدا. اگر بیاید، جای هر چیزی که
 *           داخل خود پاسخ آمار بود را می‌گیرد.
 * meta:     محتوای panel.json — چیزهایی که موتور هرگز گزارش نمی‌کند (نقش،
 *           نسخه، مشخصات میزبان). فقط جای فیلدهای *غایب* را پر می‌کند؛ هر چه
 *           سرویس زنده بدهد اولویت دارد.
 */
export function normalize(raw, portsRaw = null, meta = null) {
  const r = raw || {};
  // بعضی نسخه‌ها مشخصات میزبان را داخل یک شیء تودرتو می‌گذارند
  const h = pick(r, ['server', 'host', 'system', 'machine', 'node'], {}) || {};
  const host = typeof h === 'object' ? h : {};
  const m = (meta && typeof meta === 'object' && !Array.isArray(meta)) ? meta : {};
  const mh = (m.host && typeof m.host === 'object') ? m.host : {};

  const rawPorts = portsRaw ?? pick(r, ['ports', 'usage', 'connections', 'data'], []);
  const ports = (Array.isArray(rawPorts) ? rawPorts : [])
    .map((p) => ({
      port: pick(p, ['port', 'Port', 'local_port', 'name']),
      target: pick(p, ['target', 'remote', 'remote_addr', 'destination']),
      conns: pickNum(p, ['connections', 'conns', 'active', 'count']),
      up: pickNum(p, ['upload', 'up', 'tx', 'sent', 'bytes_sent']) ?? 0,
      down: pickNum(p, ['download', 'down', 'rx', 'received', 'bytes_recv']) ?? 0,
      /* sniffer موتور برای هر پورت فقط یک عدد *ترکیبی* می‌دهد ("2.97 KB")،
         نه تفکیک ارسال/دریافت. جدول ستون‌هایش را بر همین اساس می‌چیند. */
      traffic: pickNum(p, ['Usage', 'usage', 'ReadableUsage', 'readable_usage', 'traffic']),
      rate: pickNum(p, ['rate', 'bandwidth', 'bps', 'speed']),
    }))
    .filter((p) => p.port != null);

  const totalUp = pickNum(r, ['total_upload', 'upload', 'tx_total', 'bytes_sent'])
    ?? ports.reduce((s, p) => s + p.up, 0);
  const totalDown = pickNum(r, ['total_download', 'download', 'rx_total', 'bytes_recv'])
    ?? ports.reduce((s, p) => s + p.down, 0);

  /* موتور وضعیت را «Connected (TCPMux)» می‌دهد — ترانسپورت داخل پرانتز است و
     فیلد جداگانه‌ای برایش ندارد. */
  const statusRaw = pick(r, ['status', 'state', 'tunnel_status', 'tunnelStatus']);
  const transportInStatus = /\(([^)]+)\)/.exec(String(statusRaw ?? ''))?.[1] ?? null;

  return {
    state: normalizeState(statusRaw),
    /* موتور نقش را اعلام نمی‌کند — نه server/client و نه چیز معادلی در /stats.
       پس از panel.json می‌آید. اگر آن هم نبود «نامعلوم» می‌ماند و پنل حدس
       نمی‌زند، چون نقشِ غلط بدتر از نقشِ نامعلوم است. */
    role: pick(r, ['role', 'mode', 'side']) ?? pick(m, ['role', 'side', 'mode']),
    transport: pick(r, ['transport', 'protocol']) ?? transportInStatus
      ?? pick(m, ['transport']),
    version: pick(r, ['version', 'build']) ?? pick(m, ['version']),

    txRate: pickNum(r, ['tx_rate', 'upload_speed', 'up_bps', 'sent_rate', 'uploadSpeed']),
    rxRate: pickNum(r, ['rx_rate', 'download_speed', 'down_bps', 'recv_rate', 'downloadSpeed']),
    latency: pickNum(r, ['latency', 'ping', 'rtt', 'latency_ms']),
    conns: pickNum(r, ['connections', 'active_connections', 'conn_count', 'allConnections'])
      ?? (ports.length ? ports.reduce((s, p) => s + (p.conns || 0), 0) : null),
    goroutines: pickNum(r, ['goroutines', 'num_goroutine', 'go_routines', 'allgoroutines']),
    uptime: pickNum(r, ['uptime', 'uptime_seconds', 'started_seconds']),

    totalUp,
    totalDown,
    /* ترافیک تجمعی. موتور فقط یک عدد ترکیبی می‌دهد، نه تفکیک ارسال/دریافت:
       backhaulTraffic ترافیک خود تونل است و networkTraffic کل ماشین. اگر
       هیچ‌کدام نبود، از مجموع مصرف پورت‌ها ساخته می‌شود. */
    totalTraffic: pickNum(r, ['total_traffic', 'backhaulTraffic', 'networkTraffic'])
      ?? (ports.some((p) => p.traffic != null)
        ? ports.reduce((s, p) => s + (p.traffic ?? 0), 0)
        : null),
    ports,

    cpu: pickNum(r, ['cpu', 'cpu_percent', 'cpu_usage', 'cpuUsage']),
    /* درصد حافظه/دیسک/سواپ را موتور نمی‌دهد؛ فقط مقدار مطلق. پس *Used پر
       می‌شود و درصد null می‌ماند تا پنل به‌جای درصد، حجم را نشان دهد. */
    ram: pickNum(r, ['ram', 'memory_percent', 'mem_percent', 'memory.used_percent']),
    ramUsed: pickNum(r, ['ram_used', 'memory.used', 'mem_used', 'ramUsage']),
    ramTotal: pickNum(r, ['ram_total', 'memory.total', 'mem_total']),
    disk: pickNum(r, ['disk', 'disk_percent', 'disk.used_percent']),
    diskUsed: pickNum(r, ['disk_used', 'disk.used', 'diskUsage']),
    diskTotal: pickNum(r, ['disk_total', 'disk.total']),
    swap: pickNum(r, ['swap', 'swap_percent', 'swap.used_percent']),
    swapUsed: pickNum(r, ['swap_used', 'swap.used', 'swapUsage']),

    /* مشخصات میزبان — همه اختیاری. ترتیب جست‌وجو: شیء تودرتوی پاسخ، ریشه‌ی
       پاسخ، و آخر panel.json. هر چه هیچ‌جا نبود ردیفش از کارت حذف می‌شود. */
    host: {
      name: pick(host, ['hostname', 'name', 'host'])
        ?? pick(r, ['hostname', 'host_name', 'server_name'])
        ?? pick(mh, ['name', 'hostname']),
      ip: pick(host, ['ip', 'public_ip', 'address'])
        ?? pick(r, ['ip', 'server_ip', 'public_ip', 'bind_ip'])
        ?? pick(mh, ['ip', 'public_ip']),
      location: pick(host, ['location', 'country', 'region', 'datacenter'])
        ?? pick(r, ['location', 'country', 'region'])
        ?? pick(mh, ['location', 'country', 'region']),
      os: pick(host, ['os', 'platform', 'distro', 'os_name'])
        ?? pick(r, ['os', 'platform', 'distro'])
        ?? pick(mh, ['os', 'platform', 'distro']),
      kernel: pick(host, ['kernel', 'kernel_version', 'release'])
        ?? pick(r, ['kernel', 'kernel_version'])
        ?? pick(mh, ['kernel', 'kernel_version']),
      arch: pick(host, ['arch', 'architecture', 'goarch'])
        ?? pick(r, ['arch', 'architecture', 'goarch'])
        ?? pick(mh, ['arch', 'architecture']),
      cores: pickNum(host, ['cores', 'cpu_cores', 'cpus', 'num_cpu'])
        ?? pickNum(r, ['cores', 'cpu_cores', 'cpus', 'num_cpu'])
        ?? pickNum(mh, ['cores', 'cpu_cores', 'cpus']),
      bind: pick(host, ['bind_addr', 'bind', 'listen'])
        ?? pick(r, ['bind_addr', 'bind', 'listen', 'listen_addr'])
        ?? pick(mh, ['bind', 'bind_addr', 'listen']),
      boot: pickNum(host, ['boot_time', 'boot', 'uptime_system'])
        ?? pickNum(r, ['boot_time', 'system_uptime', 'host_uptime']),
    },

    events: (() => {
      const ev = pick(r, ['events', 'logs', 'log'], []);
      return (Array.isArray(ev) ? ev : []).map((e) => ({
        time: pick(e, ['time', 'timestamp', 'ts']),
        level: String(pick(e, ['level', 'severity'], 'info')).toLowerCase(),
        text: pick(e, ['message', 'msg', 'text'], ''),
      }));
    })(),
  };
}

function normalizeState(v) {
  const s = String(v ?? '').toLowerCase();
  if (/up|connected|online|ok|active|running/.test(s)) return 'up';
  if (/degrad|unstable|retry|warn/.test(s)) return 'degraded';
  if (/down|closed|failed|error|disconnect/.test(s)) return 'down';
  if (/connect|dial|starting|wait/.test(s)) return 'connecting';
  return 'unknown';
}

/* کلیدهایی که فقط در پاسخ *آمار* پیدا می‌شوند.
   لازم است چون موتور با sniffer روشن روی /data یک JSON کاملاً معتبر ولی
   بی‌ربط می‌دهد — آرایه‌ی مصرف پورت‌ها: [{"Port":8080,"ReadableUsage":"2.97 KB"}]
   بدون این بررسی، پنل همان را به‌عنوان آمار قبول می‌کرد، هیچ فیلدی پیدا نمی‌شد
   و همه چیز «—» و «وضعیت نامعلوم» می‌ماند. */
const STAT_KEYS = [
  'tunnelStatus', 'status', 'state', 'cpuUsage', 'cpu', 'uploadSpeed', 'tx_rate',
  'allConnections', 'connections', 'allgoroutines', 'goroutines', 'version',
];

function looksLikeStats(j) {
  return !!j && typeof j === 'object' && !Array.isArray(j)
    && STAT_KEYS.some((k) => k in j);
}

/** آرایه‌ی مصرف پورت‌ها را از یک پاسخ بیرون می‌کشد؛ اگر نبود null. */
function asPorts(j) {
  if (Array.isArray(j)) return j;
  if (j && typeof j === 'object' && Array.isArray(j.ports)) return j.ports;
  return null;
}

async function getJSON(url, timeoutMs) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: ctl.signal, headers: { Accept: 'application/json' } });
    if (!res.ok) throw new Error(`${url} → HTTP ${res.status}`);
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

/* panel.json — فایل ایستای کنار خود پنل، با چیزهایی که موتور در /stats
   نمی‌گذارد: نقش (server/client)، نسخه، و مشخصات میزبان. یک بار خوانده
   می‌شود و نتیجه — حتی اگر ۴۰۴ باشد — کش می‌شود؛ پس نبودنش نه خطاست نه
   هر ۲ ثانیه یک درخواست هدر می‌دهد. `farshub install` این فایل را می‌سازد. */
let metaPromise = null;

function panelMeta(url = 'panel.json', timeoutMs = 4000) {
  metaPromise = metaPromise ?? getJSON(url, timeoutMs).catch(() => null);
  return metaPromise;
}

/**
 * آمار را از اولین اندپوینتی می‌گیرد که واقعاً پاسخ آماری بدهد، و مصرف
 * پورت‌ها را — اگر در دسترس باشد — از اندپوینت جدا. نبودن مصرف پورت‌ها خطا
 * نیست؛ خطا فقط وقتی بالا می‌رود که هیچ آماری به دست نیاید (پنل offline شود).
 */
export async function fetchStats(
  statsUrls = ['/stats', '/data'],
  timeoutMs = 4000,
  portsUrls = ['/data'],
) {
  let stats = null;
  let ports = null;
  let lastErr = null;

  for (const url of statsUrls) {
    try {
      const j = await getJSON(url, timeoutMs);
      if (looksLikeStats(j)) { stats = j; break; }
      // پاسخ آمار نبود؛ ولی ممکن است همان مصرف پورت‌ها باشد — دوباره نمی‌گیریمش
      ports = ports ?? asPorts(j);
      lastErr = new Error(`${url} → پاسخ آمار نیست`);
    } catch (err) {
      lastErr = err;
    }
  }
  if (stats == null) throw lastErr ?? new Error('no endpoint responded');

  // نسخه‌هایی که پورت‌ها را داخل خود آمار می‌گذارند: درخواست دوم لازم نیست.
  ports = ports ?? asPorts(stats);

  for (const url of portsUrls) {
    if (ports != null) break;
    try { ports = asPorts(await getJSON(url, timeoutMs)); } catch { /* اختیاری */ }
  }

  return normalize(stats, ports, await panelMeta(undefined, timeoutMs));
}

/* peers.json — فایل ایستای دیگری کنار پنل، مثل panel.json، با «آن طرف خط» از
   دید همین ماشین (کلاینت‌های متصل روی سرور، یا سروری که کلاینت به آن وصل
   است). برخلاف panel.json کش نمی‌شود، چون سرویس آن را هر بار که وضعیت طرف
   مقابل را می‌بیند از نو می‌نویسد و محتوایش پیوسته عوض می‌شود. */
export async function fetchPeers(url = 'peers.json', timeoutMs = 4000) {
  return getJSON(url, timeoutMs);
}

/** رشته‌ی ISO یا خالی → Date؛ خالی یا نامعتبر یعنی «هرگز دیده نشده» (null). */
function asDate(v) {
  if (typeof v !== 'string' || !v.trim()) return null;
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d;
}

/**
 * payload خام peers.json → شکل واحد برای رندر؛ فایل نبود، خوانا نبود یا سمتش
 * را نگفت → null (کارت پنهان می‌ماند). سمت کارت از خود همین فایل می‌آید، نه
 * از نقش panel.json — این فایل از دید همین ماشین نوشته شده و مرجع درست
 * «آن طرف خط» است.
 */
export function normalizePeers(payload) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return null;

  const side = String(pick(payload, ['side', 'role', 'mode']) ?? '').trim().toLowerCase();
  if (side !== 'server' && side !== 'client') return null;

  /* مصرف پورت‌ها مثل /data رشته‌ی از پیش فرمت‌شده‌ی موتور است ("201.88 MB").
     به بایت تجزیه می‌شود تا با bytes() مثل جدول پورت‌ها بازفرمت شود؛ رشته‌ی
     تجزیه‌ناپذیر خام به همان شکل نمایش داده می‌شود. */
  const ports = (raw) => (Array.isArray(raw) ? raw : []).map((p) => {
    const usage = pick(p, ['usage', 'Usage', 'ReadableUsage', 'readable_usage']);
    return {
      port: pick(p, ['port', 'Port', 'local_port']),
      usage,
      usageBytes: toNum(usage),
    };
  }).filter((p) => p.port != null);

  const base = {
    side,
    generatedAt: asDate(pick(payload, ['generated_at', 'generatedAt', 'timestamp'])),
    transport: pick(payload, ['transport', 'protocol']),
  };

  if (side === 'server') {
    return {
      ...base,
      clients: (Array.isArray(payload.clients) ? payload.clients : []).map((c) => ({
        ip: pick(c, ['ip', 'address', 'remote_addr']),
        connections: pickNum(c, ['connections', 'conns', 'count']),
        firstSeen: asDate(pick(c, ['first_seen', 'firstSeen', 'since'])),
        lastSeen: asDate(pick(c, ['last_seen', 'lastSeen', 'seen'])),
        ports: ports(c.ports),
      })),
    };
  }

  const s = (payload.server && typeof payload.server === 'object') ? payload.server : {};
  return {
    ...base,
    server: {
      remoteAddr: pick(s, ['remote_addr', 'remoteAddr', 'address', 'endpoint']),
      resolvedIp: pick(s, ['resolved_ip', 'resolvedIp']) ?? pick(s, ['host', 'hostname', 'ip']),
      connections: pickNum(s, ['connections', 'conns', 'count']),
      firstSeen: asDate(pick(s, ['first_seen', 'firstSeen'])),
      lastSeen: asDate(pick(s, ['last_seen', 'lastSeen'])),
      tunnelStatus: pick(s, ['tunnel_status', 'tunnelStatus', 'status']),
    },
  };
}
