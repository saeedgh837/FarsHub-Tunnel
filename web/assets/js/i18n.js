/* ==========================================================================
   FarsHub Panel — i18n dictionary
   دو زبانه: فارسی (RTL) و انگلیسی (LTR)
   افزودن زبان جدید: یک کلید در LOCALES و یک بلوک در STRINGS اضافه کنید.
   ========================================================================== */

export const LOCALES = {
  fa: { name: 'فارسی', dir: 'rtl', lang: 'fa-IR', digits: 'arabext' },
  en: { name: 'English', dir: 'ltr', lang: 'en', digits: 'latn' },
};

export const STRINGS = {
  fa: {
    'brand.tagline': 'پایش تونل',
    'a11y.skip': 'رفتن به محتوای اصلی',
    'a11y.lang': 'تغییر زبان',
    'a11y.theme': 'تغییر تم روشن و تیره',
    'a11y.sparkline': 'نمودار روند سه دقیقه‌ی گذشته',
    'a11y.heroTitle': 'پنل پایش تونل FarsHub — گذردهی لحظه‌ای',

    'state.up': 'تونل برقرار',
    'state.degraded': 'تونل ناپایدار',
    'state.down': 'تونل قطع',
    'state.connecting': 'در حال اتصال',
    'state.unknown': 'وضعیت نامعلوم',

    'role.server': 'سرور',
    'role.client': 'کلاینت',
    'role.unknown': 'نامعلوم',
    'role.self.server': 'این دستگاه: سرور',
    'role.self.client': 'این دستگاه: کلاینت',
    'role.self.unknown': 'سمت اجرا نامعلوم',
    'role.hint.server': 'پنل روی سرور اجرا می‌شود — همان سمتی که پورت‌ها را Listen می‌کند.',
    'role.hint.client': 'پنل روی کلاینت اجرا می‌شود — همان سمتی که پشت NAT است و Dial می‌کند.',
    'role.hint.unknown': 'سرویس نقش خود را اعلام نکرده است.',

    'node.client': 'کلاینت',
    'node.client.sub': 'پشت NAT — به سرور وصل می‌شود',
    'node.server': 'سرور',
    'node.server.sub': 'کاربران به این سمت وصل می‌شوند',
    'node.self': 'همین دستگاه',
    'link.tx': 'ارسال به سرور',
    'link.rx': 'دریافت از سرور',
    'link.transport': 'ترانسپورت',
    'link.latency': 'تأخیر',

    'kpi.throughput': 'گذردهی لحظه‌ای',
    'kpi.connections': 'اتصال فعال',
    'kpi.latency': 'تأخیر تونل',
    'kpi.total': 'ترافیک کل',
    'kpi.goroutines': 'گوروتین',
    'kpi.uptime': 'مدت کارکرد',
    'kpi.hint.throughput': 'مجموع ارسال و دریافت در لحظه',
    'kpi.hint.connections': 'اتصال‌های باز روی همه‌ی پورت‌ها',
    'kpi.hint.total': 'از زمان آخرین راه‌اندازی سرویس',

    'ports.title': 'پورت‌ها',
    'ports.subtitle': 'ترافیک به تفکیک پورت',
    'ports.col.port': 'پورت',
    'ports.col.target': 'مقصد',
    'ports.col.conns': 'اتصال',
    'ports.col.up': 'ارسال',
    'ports.col.down': 'دریافت',
    'ports.col.traffic': 'ترافیک',
    'ports.col.rate': 'نرخ',
    'ports.col.share': 'سهم',
    'ports.empty.title': 'هنوز ترافیکی ثبت نشده',
    'ports.empty.body': 'پورت‌ها را در کانفیگ تعریف کنید و مقدار sniffer را true بگذارید — بدون آن، سرویس مصرف هر پورت را ثبت نمی‌کند.',
    'ports.nomatch.title': 'نتیجه‌ای پیدا نشد',
    'ports.nomatch.body': 'عبارت جست‌وجو با هیچ پورت یا مقصدی مطابقت ندارد.',
    'ports.search': 'جست‌وجوی پورت یا مقصد',
    'ports.total': 'مجموع',

    'peers.title.server': 'کلاینت‌های متصل',
    'peers.title.client': 'سرور متصل',
    'peers.empty.server': 'کلاینتی متصل نیست',
    'peers.col.ip': 'نشانی IP',
    'peers.col.first': 'شروع اتصال',
    'peers.col.last': 'آخرین فعالیت',
    'peers.col.ports': 'پورت‌ها',
    'peers.remote': 'نشانی سرور',
    'peers.resolved': 'IP حل‌شده',
    'peers.status': 'وضعیت تونل',
    'peers.ago': 'پیش',
    'peers.updated': 'آخرین به‌روزرسانی',

    'sys.title': 'منابع سیستم',
    'sys.cpu': 'پردازنده',
    'sys.ram': 'حافظه',
    'sys.disk': 'دیسک',
    'sys.swap': 'سوآپ',
    'sys.of': 'از',

    'srv.title': 'مشخصات سرور',
    'srv.subtitle': 'همان دستگاهی که این پنل روی آن اجرا می‌شود',
    'srv.host': 'نام میزبان',
    'srv.ip': 'نشانی IP',
    'srv.location': 'موقعیت',
    'srv.os': 'سیستم‌عامل',
    'srv.kernel': 'کرنل',
    'srv.arch': 'معماری',
    'srv.cores': 'هسته‌ی پردازنده',
    'srv.ram': 'حافظه‌ی کل',
    'srv.disk': 'فضای کل',
    'srv.bind': 'نشانی Bind',
    'srv.version': 'نسخه‌ی FarsHub',
    'srv.boot': 'روشن از',
    'srv.copy': 'رونوشت',
    'srv.copied': 'رونوشت شد',
    'srv.empty': 'این نسخه از سرویس مشخصات میزبان را گزارش نمی‌کند.',

    'sup.title': 'پشتیبانی',
    'sup.body': 'برای راه‌اندازی، خرید سرور یا رفع اشکال تونل در تلگرام پیام بدهید.',
    'sup.cta': 'پیام در تلگرام',

    'log.title': 'رویدادها',
    'log.empty': 'رویدادی ثبت نشده است.',
    'log.level.info': 'اطلاع',
    'log.level.warn': 'هشدار',
    'log.level.error': 'خطا',

    'meta.transport': 'ترانسپورت',
    'meta.role': 'نقش',
    'meta.version': 'نسخه',
    'meta.updated': 'آخرین به‌روزرسانی',
    'meta.live': 'زنده',
    'meta.paused': 'متوقف',
    'meta.stale': 'داده قدیمی',
    'meta.offline': 'اتصال به سرویس قطع است',
    'meta.retry': 'تلاش دوباره',

    'unit.ms': 'میلی‌ثانیه',
    'unit.day': 'روز',
    'unit.hour': 'ساعت',
    'unit.min': 'دقیقه',
    'unit.sec': 'ثانیه',
    'unit.none': '—',
  },

  en: {
    'brand.tagline': 'Tunnel monitor',
    'a11y.skip': 'Skip to main content',
    'a11y.lang': 'Change language',
    'a11y.theme': 'Toggle light and dark theme',
    'a11y.sparkline': 'Trend over the last three minutes',
    'a11y.heroTitle': 'FarsHub tunnel monitor — live throughput',

    'state.up': 'Tunnel up',
    'state.degraded': 'Tunnel unstable',
    'state.down': 'Tunnel down',
    'state.connecting': 'Connecting',
    'state.unknown': 'Status unknown',

    'role.server': 'Server',
    'role.client': 'Client',
    'role.unknown': 'Unknown',
    'role.self.server': 'This machine: server',
    'role.self.client': 'This machine: client',
    'role.self.unknown': 'Side unknown',
    'role.hint.server': 'The panel runs on the server — the side that listens on the ports.',
    'role.hint.client': 'The panel runs on the client — the side behind NAT that dials out.',
    'role.hint.unknown': 'The service did not report its role.',

    'node.client': 'Client',
    'node.client.sub': 'Behind NAT — dials the server',
    'node.server': 'Server',
    'node.server.sub': 'Users connect on this side',
    'node.self': 'This machine',
    'link.tx': 'Sent to server',
    'link.rx': 'Received from server',
    'link.transport': 'Transport',
    'link.latency': 'Latency',

    'kpi.throughput': 'Live throughput',
    'kpi.connections': 'Active connections',
    'kpi.latency': 'Tunnel latency',
    'kpi.total': 'Total traffic',
    'kpi.goroutines': 'Goroutines',
    'kpi.uptime': 'Uptime',
    'kpi.hint.throughput': 'Sent and received, combined',
    'kpi.hint.connections': 'Open connections across all ports',
    'kpi.hint.total': 'Since the service last started',

    'ports.title': 'Ports',
    'ports.subtitle': 'Traffic per port',
    'ports.col.port': 'Port',
    'ports.col.target': 'Target',
    'ports.col.conns': 'Conns',
    'ports.col.up': 'Sent',
    'ports.col.down': 'Received',
    'ports.col.traffic': 'Traffic',
    'ports.col.rate': 'Rate',
    'ports.col.share': 'Share',
    'ports.empty.title': 'No traffic recorded yet',
    'ports.empty.body': 'Define the ports in the config and set sniffer = true — without it the service does not record per-port usage.',
    'ports.nomatch.title': 'No matches',
    'ports.nomatch.body': 'No port or target matches that search.',
    'ports.search': 'Search port or target',
    'ports.total': 'Total',

    'peers.title.server': 'Connected Clients',
    'peers.title.client': 'Connected Server',
    'peers.empty.server': 'No clients connected',
    'peers.col.ip': 'IP address',
    'peers.col.first': 'First seen',
    'peers.col.last': 'Last seen',
    'peers.col.ports': 'Ports',
    'peers.remote': 'Server address',
    'peers.resolved': 'Resolved IP',
    'peers.status': 'Tunnel status',
    'peers.ago': 'ago',
    'peers.updated': 'Last updated',

    'sys.title': 'System resources',
    'sys.cpu': 'CPU',
    'sys.ram': 'Memory',
    'sys.disk': 'Disk',
    'sys.swap': 'Swap',
    'sys.of': 'of',

    'srv.title': 'Server details',
    'srv.subtitle': 'The machine this panel runs on',
    'srv.host': 'Hostname',
    'srv.ip': 'IP address',
    'srv.location': 'Location',
    'srv.os': 'Operating system',
    'srv.kernel': 'Kernel',
    'srv.arch': 'Architecture',
    'srv.cores': 'CPU cores',
    'srv.ram': 'Total memory',
    'srv.disk': 'Total storage',
    'srv.bind': 'Bind address',
    'srv.version': 'FarsHub version',
    'srv.boot': 'Booted',
    'srv.copy': 'Copy',
    'srv.copied': 'Copied',
    'srv.empty': 'This build of the service does not report host details.',

    'sup.title': 'Support',
    'sup.body': 'Message on Telegram for setup, a server, or help with the tunnel.',
    'sup.cta': 'Message on Telegram',

    'log.title': 'Events',
    'log.empty': 'No events recorded.',
    'log.level.info': 'Info',
    'log.level.warn': 'Warning',
    'log.level.error': 'Error',

    'meta.transport': 'Transport',
    'meta.role': 'Role',
    'meta.version': 'Version',
    'meta.updated': 'Last updated',
    'meta.live': 'Live',
    'meta.paused': 'Paused',
    'meta.stale': 'Stale data',
    'meta.offline': 'Not connected to the service',
    'meta.retry': 'Try again',

    'unit.ms': 'ms',
    'unit.day': 'd',
    'unit.hour': 'h',
    'unit.min': 'm',
    'unit.sec': 's',
    'unit.none': '—',
  },
};

/* ---------------------------------------------------------------- runtime -- */

const STORE_KEY = 'farshub.lang';
const FALLBACK = 'en';

let current = detect();

function detect() {
  try {
    const saved = localStorage.getItem(STORE_KEY);
    if (saved && LOCALES[saved]) return saved;
  } catch { /* storage blocked — fall through to navigator */ }
  const nav = (navigator.languages || [navigator.language || '']).join(',');
  return /\bfa\b|-IR\b/i.test(nav) ? 'fa' : 'en';
}

export function locale() {
  return current;
}

export function setLocale(code) {
  if (!LOCALES[code]) return current;
  current = code;
  try { localStorage.setItem(STORE_KEY, code); } catch { /* ignore */ }
  resetFormatters();
  applyDocumentLocale();
  return current;
}

export function toggleLocale() {
  const codes = Object.keys(LOCALES);
  return setLocale(codes[(codes.indexOf(current) + 1) % codes.length]);
}

/** Translate a key. Missing keys fall back to English, then to the key itself. */
export function t(key) {
  const table = STRINGS[current] || {};
  if (key in table) return table[key];
  const fb = STRINGS[FALLBACK] || {};
  return key in fb ? fb[key] : key;
}

export function applyDocumentLocale() {
  const meta = LOCALES[current];
  const html = document.documentElement;
  html.lang = meta.lang;
  html.dir = meta.dir;
  html.dataset.locale = current;
}

/* --------------------------------------------------------------- formatting -- */

const nfCache = new Map();

function nf(opts = {}) {
  const meta = LOCALES[current];
  const key = current + JSON.stringify(opts);
  if (!nfCache.has(key)) {
    nfCache.set(key, new Intl.NumberFormat(meta.lang, {
      numberingSystem: meta.digits,
      ...opts,
    }));
  }
  return nfCache.get(key);
}

/** Integer with locale digits and grouping. */
export function num(v, opts) {
  if (v == null || Number.isNaN(v)) return t('unit.none');
  return nf(opts).format(v);
}

/** Percentage 0–100 → "٤٢٪" / "42%". */
export function pct(v, digits = 0) {
  if (v == null || Number.isNaN(v)) return t('unit.none');
  return nf({ style: 'percent', minimumFractionDigits: digits, maximumFractionDigits: digits })
    .format(v / 100);
}

const BYTE_UNITS = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
const BIT_UNITS = ['bps', 'Kbps', 'Mbps', 'Gbps', 'Tbps'];

function scale(value, units, step) {
  let v = Math.abs(Number(value) || 0);
  let i = 0;
  while (v >= step && i < units.length - 1) { v /= step; i += 1; }
  const digits = v < 10 && i > 0 ? 1 : 0;
  return {
    value: nf({ minimumFractionDigits: digits, maximumFractionDigits: digits }).format(v),
    unit: units[i],
  };
}

/** Bytes → { value, unit }. Unit stays Latin — these are universal symbols. */
export function bytes(v) {
  return scale(v, BYTE_UNITS, 1024);
}

/** Bytes per second → { value, unit } با واحد بیت.
    موتور نرخ را بایت بر ثانیه می‌دهد ("982.00 B/s" — روی سرور تأیید شد) ولی
    پهنای باند در فارسی و انگلیسی هر دو با bit/s گفته می‌شود، پس ×۸ می‌کنیم. */
export function bitrate(v) {
  return scale((Number(v) || 0) * 8, BIT_UNITS, 1000);
}

/** Seconds → compact duration, e.g. "٣ روز ٤ ساعت" / "3d 4h". */
export function duration(totalSeconds) {
  const s = Math.max(0, Math.floor(Number(totalSeconds) || 0));
  const parts = [
    [Math.floor(s / 86400), 'unit.day'],
    [Math.floor((s % 86400) / 3600), 'unit.hour'],
    [Math.floor((s % 3600) / 60), 'unit.min'],
    [s % 60, 'unit.sec'],
  ];
  const shown = parts.filter(([n]) => n > 0).slice(0, 2);
  if (!shown.length) return `${num(0)} ${t('unit.sec')}`;
  const joiner = current === 'fa' ? ' و ' : ' ';
  return shown.map(([n, k]) => `${num(n)} ${t(k)}`).join(joiner);
}

/** Wall-clock time for the "last updated" stamp. */
export function clock(date = new Date()) {
  const meta = LOCALES[current];
  return new Intl.DateTimeFormat(meta.lang, {
    numberingSystem: meta.digits,
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).format(date);
}

/** Date + wall-clock time for stamps that name a moment, not just a time —
    مثل مهر «آخرین به‌روزرسانی» فایل peers که می‌گوید داده از چه تاریخی است. */
export function dateTime(date = new Date()) {
  const meta = LOCALES[current];
  return new Intl.DateTimeFormat(meta.lang, {
    numberingSystem: meta.digits,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).format(date);
}

/** Flush cached formatters after a locale switch. */
export function resetFormatters() {
  nfCache.clear();
}
