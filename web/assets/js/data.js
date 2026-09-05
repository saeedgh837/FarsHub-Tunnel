/* ==========================================================================
   FarsHub Panel — data adapter
   باینری آپ‌استریم روی /data و /stats سرو می‌کند. شکل دقیق پاسخ نسخه‌به‌نسخه
   متفاوت است، پس اینجا با چند نام محتمل برای هر فیلد کار می‌کنیم و هر چه
   پیدا نشد null می‌ماند (پنل «—» نشان می‌دهد، عدد جعلی نمی‌سازد).
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

function toNum(v) {
  if (v == null || typeof v === 'object' || typeof v === 'boolean') return null;
  const n = typeof v === 'string' ? parseFloat(v.replace(/[^\d.-]/g, '')) : Number(v);
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

/** پاسخ خام سرویس → شکل واحدی که رندرها مصرف می‌کنند. */
export function normalize(raw) {
  const r = raw || {};
  // بعضی نسخه‌ها مشخصات میزبان را داخل یک شیء تودرتو می‌گذارند
  const h = pick(r, ['server', 'host', 'system', 'machine', 'node'], {}) || {};
  const host = typeof h === 'object' ? h : {};

  const rawPorts = pick(r, ['ports', 'usage', 'connections', 'data'], []);
  const ports = (Array.isArray(rawPorts) ? rawPorts : [])
    .map((p) => ({
      port: pick(p, ['port', 'local_port', 'name']),
      target: pick(p, ['target', 'remote', 'remote_addr', 'destination']),
      conns: pickNum(p, ['connections', 'conns', 'active', 'count']),
      up: pickNum(p, ['upload', 'up', 'tx', 'sent', 'bytes_sent']) ?? 0,
      down: pickNum(p, ['download', 'down', 'rx', 'received', 'bytes_recv']) ?? 0,
      rate: pickNum(p, ['rate', 'bandwidth', 'bps', 'speed']),
    }))
    .filter((p) => p.port != null);

  const totalUp = pickNum(r, ['total_upload', 'upload', 'tx_total', 'bytes_sent'])
    ?? ports.reduce((s, p) => s + p.up, 0);
  const totalDown = pickNum(r, ['total_download', 'download', 'rx_total', 'bytes_recv'])
    ?? ports.reduce((s, p) => s + p.down, 0);

  return {
    state: normalizeState(pick(r, ['status', 'state', 'tunnel_status'])),
    role: pick(r, ['role', 'mode', 'side']),
    transport: pick(r, ['transport', 'protocol']),
    version: pick(r, ['version', 'build']),

    txRate: pickNum(r, ['tx_rate', 'upload_speed', 'up_bps', 'sent_rate']),
    rxRate: pickNum(r, ['rx_rate', 'download_speed', 'down_bps', 'recv_rate']),
    latency: pickNum(r, ['latency', 'ping', 'rtt', 'latency_ms']),
    conns: pickNum(r, ['connections', 'active_connections', 'conn_count'])
      ?? (ports.length ? ports.reduce((s, p) => s + (p.conns || 0), 0) : null),
    goroutines: pickNum(r, ['goroutines', 'num_goroutine', 'go_routines']),
    uptime: pickNum(r, ['uptime', 'uptime_seconds', 'started_seconds']),

    totalUp,
    totalDown,
    ports,

    cpu: pickNum(r, ['cpu', 'cpu_percent', 'cpu_usage']),
    ram: pickNum(r, ['ram', 'memory_percent', 'mem_percent', 'memory.used_percent']),
    ramUsed: pickNum(r, ['ram_used', 'memory.used', 'mem_used']),
    ramTotal: pickNum(r, ['ram_total', 'memory.total', 'mem_total']),
    disk: pickNum(r, ['disk', 'disk_percent', 'disk.used_percent']),
    diskUsed: pickNum(r, ['disk_used', 'disk.used']),
    diskTotal: pickNum(r, ['disk_total', 'disk.total']),
    swap: pickNum(r, ['swap', 'swap_percent', 'swap.used_percent']),

    /* مشخصات میزبان — همه اختیاری. هر چه سرویس نفرستد `—` می‌شود.
       در r و در شیء تودرتو (server/host/system) هر دو می‌گردیم. */
    host: {
      name: pick(host, ['hostname', 'name', 'host'])
        ?? pick(r, ['hostname', 'host_name', 'server_name']),
      ip: pick(host, ['ip', 'public_ip', 'address'])
        ?? pick(r, ['ip', 'server_ip', 'public_ip', 'bind_ip']),
      location: pick(host, ['location', 'country', 'region', 'datacenter'])
        ?? pick(r, ['location', 'country', 'region']),
      os: pick(host, ['os', 'platform', 'distro', 'os_name'])
        ?? pick(r, ['os', 'platform', 'distro']),
      kernel: pick(host, ['kernel', 'kernel_version', 'release'])
        ?? pick(r, ['kernel', 'kernel_version']),
      arch: pick(host, ['arch', 'architecture', 'goarch'])
        ?? pick(r, ['arch', 'architecture', 'goarch']),
      cores: pickNum(host, ['cores', 'cpu_cores', 'cpus', 'num_cpu'])
        ?? pickNum(r, ['cores', 'cpu_cores', 'cpus', 'num_cpu']),
      bind: pick(host, ['bind_addr', 'bind', 'listen'])
        ?? pick(r, ['bind_addr', 'bind', 'listen', 'listen_addr']),
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

/** Fetch با timeout. خطا را بالا می‌دهد تا لایه‌ی بالا حالت offline نشان دهد. */
export async function fetchStats(endpoints = ['/data', '/stats'], timeoutMs = 4000) {
  let lastErr;
  for (const url of endpoints) {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), timeoutMs);
    try {
      const res = await fetch(url, { signal: ctl.signal, headers: { Accept: 'application/json' } });
      if (!res.ok) throw new Error(`${url} → HTTP ${res.status}`);
      return normalize(await res.json());
    } catch (err) {
      lastErr = err;
    } finally {
      clearTimeout(timer);
    }
  }
  throw lastErr ?? new Error('no endpoint responded');
}
