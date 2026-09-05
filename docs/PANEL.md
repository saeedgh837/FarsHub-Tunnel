# پنل وب FarsHub

پنل ایستا و دوزبانه (فارسی RTL / انگلیسی LTR) برای پایش تونل. بدون هیچ
وابستگی به CDN؛ فونت‌ها محلی‌اند و کل پنل چند فایل ساده است.

```
web/index.html                 مارک‌آپ، همه‌ی رشته‌ها با data-i18n
web/assets/css/panel.css       توکن‌های طراحی + استایل کامپوننت‌ها + دو تم
web/assets/js/i18n.js          جدول زبان‌ها، دیکشنری fa/en، لایه‌ی فرمت اعداد
web/assets/js/data.js          آداپتور /data → شکل واحد داخلی
web/assets/js/sparkline.js     نمودار SVG خالص + بافر حلقه‌ای
web/assets/js/app.js           رندر، polling، تم، زبان، فیلتر
web/assets/fonts/              Vazirmatn + JetBrains Mono (woff2 + مجوز OFL)
web/devserver.py               فقط برای توسعه — هرگز deploy نکنید
```

---

## ⚠️ این پنل جای پنل داخلی موتور اجرا را نمی‌گیرد

موتور اجرا (`bin/farshub-core`) پنل **خودش** را روی `web_port` سرو می‌کند و آن
HTML داخل خودش embed شده — با برندینگ آپ‌استریم («Backhaul Traffic»،
`<title>Backhaul`). موتور stripped است، پس تزریق این پنل به داخلش عملی نیست.
دو راه واقعی وجود دارد:

**راه ۱ — سرو جداگانه (بدون دست‌زدن به موتور اجرا).**
`web_port` را روشن کنید، پنل را با یک وب‌سرور ایستا بالا بیاورید و `/data` را
با reverse proxy به موتور بدهید:

```nginx
server {
  listen 127.0.0.1:8088;
  root /var/lib/farshub/web;
  index index.html;
  location = /data { proxy_pass http://127.0.0.1:2060/data; }
  location = /stats { proxy_pass http://127.0.0.1:2060/stats; }
}
```

خلاصه‌ی همین مراحل را `farshub panel` هم می‌دهد.

**نکته‌ی امنیتی:** پنل داخلی موتور هیچ احراز هویتی ندارد. `web_port` را روی
`127.0.0.1` نگه دارید و اگر لازم است از بیرون ببینید، جلوی nginx را با
`auth_basic` + TLS ببندید، یا به‌جای انتشار عمومی از SSH tunnel استفاده کنید:

```bash
ssh -N -L 8088:127.0.0.1:8088 root@SERVER_IP
```

`farshub check` هشدار می‌دهد اگر `web_port` روی مقداری غیر از `0` باشد.

**راه ۲ — build از سورس آپ‌استریم.** فایل‌های `internal/web/` را با محتوای
`web/` عوض کنید و دوباره کامپایل کنید. این تنها راه برای برندسازی داخل خود
موتور اجرا و حذف کد license/telemetry است (توضیح در [ORIGIN.md](ORIGIN.md)).

---

## پیش‌نمایش محلی

```bash
python web/devserver.py --port 8770
```

روی `127.0.0.1` بایند می‌شود و `/data` را با اعداد ساختگی جواب می‌دهد، فقط برای
دیدن ظاهر پنل. این سرور auth ندارد و برای production نیست.

برای دیدن رفتار پنل وقتی سرویس فیلدهای اختیاری را **نمی‌فرستد** (که روی
موتور اجرای واقعی محتمل است)، از `?bare=1` استفاده کنید:

```bash
curl -s 'http://127.0.0.1:8770/data?bare=1' | head -c 300
```

در آن حالت مشخصات میزبان، نسخه، و مجموع بایت‌ها حذف می‌شوند و کارت مشخصات سرور
به‌جای ستونی از `—` پیام خالی نشان می‌دهد.

---

## فرض‌های `data.js` روی شکل پاسخ

شکل خروجی `/data` بین نسخه‌های آپ‌استریم ثابت نیست، پس `data.js` برای هر فیلد
چند نام محتمل را امتحان می‌کند و **اولین مقدار عددی معتبر** را برمی‌دارد. هر چه
پیدا نشود `null` می‌ماند و پنل `—` نشان می‌دهد — عدد جعلی ساخته نمی‌شود.

| فیلد داخلی | نام‌های پذیرفته‌شده در JSON |
| --- | --- |
| `state` | `status`, `state`, `tunnel_status` |
| `role` | `role`, `mode`, `side` |
| `transport` | `transport`, `protocol` |
| `txRate` | `tx_rate`, `upload_speed`, `up_bps`, `sent_rate` |
| `rxRate` | `rx_rate`, `download_speed`, `down_bps`, `recv_rate` |
| `latency` | `latency`, `ping`, `rtt`, `latency_ms` |
| `conns` | `connections`, `active_connections`, `conn_count` |
| `goroutines` | `goroutines`, `num_goroutine`, `go_routines` |
| `uptime` | `uptime`, `uptime_seconds`, `started_seconds` |
| `cpu` | `cpu`, `cpu_percent`, `cpu_usage` |
| `ram` | `ram`, `memory_percent`, `mem_percent`, `memory.used_percent` |
| `disk` | `disk`, `disk_percent`, `disk.used_percent` |
| `swap` | `swap`, `swap_percent`, `swap.used_percent` |
| `version` | `version`, `build` |
| `ports[]` | `ports`, `usage`, `connections`, `data` |
| `events[]` | `events`, `logs`, `log` |

داخل هر آیتم `ports[]`: `port`/`local_port`/`name`، `target`/`remote`/
`remote_addr`/`destination`، `connections`/`conns`/`active`/`count`،
`upload`/`up`/`tx`/`sent`/`bytes_sent`، و متناظر دانلود.

### مشخصات میزبان (`host.*`)

کارت «مشخصات سرور» این فیلدها را مصرف می‌کند. برای هر کدام **اول** داخل شیء
تودرتو (`server` یا `host` یا `system` یا `machine` یا `node`) و بعد در ریشه‌ی
پاسخ گشته می‌شود، پس هر دو شکل زیر کار می‌کند:

```json
{ "server": { "hostname": "fra-edge-01", "ip": "203.0.113.42" } }
{ "hostname": "fra-edge-01", "server_ip": "203.0.113.42" }
```

| فیلد داخلی | نام‌های پذیرفته‌شده (تودرتو / ریشه) |
| --- | --- |
| `host.name` | `hostname`, `name`, `host` / `hostname`, `host_name`, `server_name` |
| `host.ip` | `ip`, `public_ip`, `address` / `ip`, `server_ip`, `public_ip`, `bind_ip` |
| `host.location` | `location`, `country`, `region`, `datacenter` / همان‌ها |
| `host.os` | `os`, `platform`, `distro`, `os_name` / `os`, `platform`, `distro` |
| `host.kernel` | `kernel`, `kernel_version`, `release` / `kernel`, `kernel_version` |
| `host.arch` | `arch`, `architecture`, `goarch` / همان‌ها |
| `host.cores` | `cores`, `cpu_cores`, `cpus`, `num_cpu` / همان‌ها |
| `host.bind` | `bind_addr`, `bind`, `listen` / + `listen_addr` |
| `host.boot` | `boot_time`, `boot`, `uptime_system` / `boot_time`, `system_uptime`, `host_uptime` |

**همه‌ی این‌ها اختیاری‌اند و آپ‌استریم ممکن است هیچ‌کدام را نفرستد.** برخلاف
بقیه‌ی پنل که برای مقدار غایب `—` می‌گذارد، این کارت ردیف‌های بی‌مقدار را
**حذف** می‌کند تا ستونی از `—` نسازد؛ اگر هیچ فیلدی نیامد، کارت حالت خالی
نشان می‌دهد. حافظه‌ی کل و فضای کل از همان `memory.total`/`disk.total` گیج‌ها
می‌آیند، نه از `host`.

`state` با regex دسته‌بندی می‌شود: `up | degraded | down | connecting | unknown`.
مقادیر بایت بر ثانیه فرض می‌شوند و در UI به bit/s تبدیل می‌شوند.

اگر شکل پاسخ نسخه‌ی شما فیلد دیگری دارد، فقط نامش را به آرایه‌ی همان سطر در
`normalize()` اضافه کنید — جای دیگری تغییر لازم نیست.

---

## چیدمان پنل

از بالا به پایین:

| بخش | چه چیزی |
| --- | --- |
| `.link` | وضعیت تونل + چیپ «این دستگاه: سرور/کلاینت»، گذردهی، نمودار سیم |
| `.ribbon` | نقش، ترانسپورت، مدت کارکرد، گوروتین، نسخه، آخرین بروزرسانی |
| `.tiles` | چهار KPI با sparkline |
| `.card` ×۳ | پورت‌ها، منابع سیستم، رویدادها |
| `.split` | مشخصات سرور + کارت پشتیبانی تلگرام |

نوار `.ribbon` عمداً بالای صفحه است، نه ته آن: این مقادیر هویت اجرا را می‌گویند
و باید همان اول خوانده شوند. شش ستون در ≥68rem، سه ستون در ≥40rem، دو ستون
پایین‌تر.

### «این دستگاه کدام سمت تونل است؟»

در معماری تونل معکوس **کلاینت همیشه dial می‌کند و سرور همیشه Listen**، که
برعکس انتظار رایج است — پس پنل این را صریح نشان می‌دهد. `sideOf()` در `app.js`
رشته‌ی `role` سرویس را دسته‌بندی می‌کند:

```js
/server|serve|remote|edge|kharej/  → 'server'
/client|local|iran|nat/            → 'client'
هیچ‌کدام                            → 'unknown'
```

نتیجه سه نمایش هم‌زمان را می‌راند، همه از یک منبع: چیپ رنگی کنار وضعیت تونل
(سبز = سرور، بنفش = کلاینت) با تولتیپ توضیحی، نشان «همین دستگاه» و حلقه‌ی
accent روی گره‌ی متناظر در نمودار سیم، و نقطه‌ی رنگی کنار «نقش» در ribbon.
اگر نقش نامعلوم بود هر سه به حالت خنثی می‌روند — حدس زده نمی‌شود.

### دکمه‌ی رونوشت در مشخصات سرور

نام میزبان، نشانی IP و نشانی Bind دکمه‌ی رونوشت دارند. چون سطرهای `#specs` هر
۲ ثانیه بازساخته می‌شوند، شنونده روی خود `#specs` است (event delegation) نه روی
دکمه‌ها. `navigator.clipboard` در HTTP بدون localhost بلاک است و آن‌جا کلیک
بی‌صدا بی‌اثر می‌ماند. دکمه با هاور/فوکوس دیده می‌شود، و در موبایل همیشه — چون
هاور وجود ندارد.

### کارت پشتیبانی

تنها بلوکی در پنل با زمینه‌ی accent، عمداً، تا تک نقطه‌ی فراخوان صفحه باشد.
لینک تلگرام در `index.html` هاردکد است (`https://t.me/vpsfa` با
`rel="noopener noreferrer"`) و متن‌هایش با کلیدهای `sup.*` ترجمه می‌شوند.

---

## رفتار زمان اجرا

- هر ۲ ثانیه `/data` و اگر جواب نداد `/stats` (timeout ۴ ثانیه با `AbortController`).
- یک شکست ⇒ برچسب «داده قدیمی»؛ دو شکست پیاپی ⇒ «اتصال به سرویس قطع است» و
  وضعیت تونل نامعلوم. آخرین داده‌ی سالم روی صفحه می‌ماند.
- تب پنهان ⇒ polling متوقف می‌شود (برچسب «متوقف»)، با برگشت به تب ادامه می‌یابد.
- نمودارها ۹۰ نمونه نگه می‌دارند (≈ ۳ دقیقه).
- تم و زبان در `localStorage` با کلیدهای `farshub.theme` و `farshub.lang` ذخیره
  می‌شوند. تم پیش از رندر در یک اسکریپت inline ست می‌شود تا فلش سفید رخ ندهد.

---

## افزودن زبان سوم

سه تغییر کافی است. مثال برای عربی:

**۱) در `i18n.js` به `LOCALES` اضافه کنید:**

```js
export const LOCALES = {
  fa: { name: 'فارسی',  dir: 'rtl', lang: 'fa-IR', digits: 'arabext' },
  en: { name: 'English', dir: 'ltr', lang: 'en',    digits: 'latn' },
  ar: { name: 'العربية', dir: 'rtl', lang: 'ar',    digits: 'arab' },
};
```

`digits` همان `numberingSystem` در `Intl` است: `latn`, `arabext` (۰۱۲ فارسی)،
`arab` (٠١٢ عربی).

**۲) یک بلوک در `STRINGS` با همان کلیدها بسازید.** کلید جا افتاده خطا نمی‌دهد —
`t()` به انگلیسی و بعد به خود کلید برمی‌گردد، پس می‌توانید تدریجی ترجمه کنید.

**۳) اگر خط عربی/فارسی نیست، فونت را چک کنید.** ترتیب دکمه‌ی زبان خودکار است
(چرخشی روی کلیدهای `LOCALES`) و دکمه همیشه نام زبان *بعدی* را نشان می‌دهد.

---

## نکته‌های تایپوگرافی که نباید خراب شوند

- **`letter-spacing` روی خط عربی ممنوع.** حروف را از هم جدا می‌کند. به همین دلیل
  کلاس `.tracked` فقط زیر `[data-locale='en']` مقدار می‌گیرد.
- **اعداد همیشه LTR.** `.num` و `.mono` با `direction: ltr` و
  `unicode-bidi: isolate` ست شده‌اند تا `443` داخل متن راست‌چین جابه‌جا نشود.
- **`Vazirmatn` داخل استک mono هم هست، عمداً.** بازه‌ی `unicode-range` فونت
  JetBrains ارقام فارسی (U+06F0–06F9) را ندارد؛ بدون این fallback ارقام فارسی
  به یک mono سیستمی می‌افتند.
- **فقط دو وزن mono بارگذاری می‌شود** (۴۰۰ و ۷۰۰). عناصر با `font-weight: 600`
  طبق قواعد تطبیق فونت به ۷۰۰ می‌رسند، پس فایل Medium لازم نیست. اگر وزن ۵۰۰
  را جایی به‌کار بردید، `JetBrainsMono-Medium.woff2` را برگردانید.
- **نام فایل فونت‌ها براکت ندارد.** فایل اصلی آپ‌استریم `Vazirmatn[wght].woff2`
  است؛ براکت‌ها در URL باید encode شوند و اگر `<link rel=preload>` و
  `@font-face` یکسان encode نکنند، مرورگر دو درخواست جدا می‌فرستد و preload
  هدر می‌رود. فایل به `Vazirmatn-Variable.woff2` تغییر نام داده شده.
- **جهت انیمیشن ریل‌ها معنایی است، نه بصری.** ریل پایین `animation-direction:
  reverse` دارد تا جریان همیشه client→server خوانده شود و RTL معنا را برنگرداند.
- سرعت ریل از گذردهی واقعی مشتق می‌شود (مقیاس لگاریتمی)؛ زیر ۱ کیلوبایت بر
  ثانیه متوقف و کم‌رنگ می‌شود.

`prefers-reduced-motion` و `@media print` هر دو پوشش داده شده‌اند.
