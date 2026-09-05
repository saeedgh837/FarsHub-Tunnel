# مبدأ موتور اجرا و هشدارهای امنیتی

این سند ثبت می‌کند که `bin/farshub-core` واقعاً چیست. برندسازی FarsHub لایه‌ی
بیرونی را پوشش می‌دهد — دستور `farshub`، نام سرویس، مسیرها، کانفیگ، و فیلتر
برندینگ روی خروجی — ولی **خودِ موتور اجرا دست‌نخورده است.**

## شناسنامه‌ی موتور اجرا

| مورد | مقدار |
|---|---|
| نام فایل در FarsHub | `bin/farshub-core` |
| نام اصلی | `backhaul_premium` |
| MD5 | `2f86ffb6ab33de43abfc606e12a8d972` |
| حجم | 13,664,440 بایت |
| نوع | ELF 64-bit LSB executable, x86-64, statically linked, stripped |
| BuildID (sha1) | `7cd26ee38a0b089aaea7f79ab5895aeff63b80b3` |
| پروژه‌ی مبدأ | `github.com/musix/backhaul` |
| نسخه | `0.6.5-SNAPSHOT-012adfc` |
| commit | `012adfc03588685d9263b4987bee8faf4b83f0a7` |
| تاریخ build | `2025-02-26T18:02:53Z` |
| ابزار build | `goreleaser`, Go `gc`, `CGO_ENABLED=0`, `GOAMD64=v1` |
| برندینگ داخلی | `Backhaul Premium %s https://t.me/dawsh42` |

اطلاعات بالا از Go build info و symbol table داخل موتور اجرا استخراج شده است.

## برندسازی: چه چیزی پوشش داده شد و چه چیزی نه

**پوشش داده شد** — کاربر در مسیر معمول استفاده فقط FarsHub می‌بیند:

| جا | روش |
|---|---|
| دستوری که تایپ می‌شود | `farshub` (اسکریپت sh)؛ موتور به `libexec` منتقل شد |
| لاگ و خروجی ترمینال | فیلتر `sed` در `run` و `logs` — [CLI.md](CLI.md) |
| `farshub version` | رشته‌ی برندینگ آپ‌استریم از خروجی پاک می‌شود |
| نام سرویس، مسیرها، کانفیگ | `farshub-*.service`, `/etc/farshub`, `/var/log/farshub` |
| journal | `SyslogIdentifier=farshub` در یونیت‌ها |
| پنل وب | پنل مستقل FarsHub در `web/` |

**پوشش داده نشد** — این‌ها همچنان برندینگ آپ‌استریم را دارند:

- **پنل داخلی موتور روی `web_port`.** HTML آن داخل موتور کامپایل شده و
  «Backhaul Traffic» و `<title>Backhaul` دارد. به‌همین دلیل پیش‌فرض `web_port`
  در این مخزن `0` است و پنل مستقل `web/` جای آن را می‌گیرد.
- **رشته‌های داخل خود فایل موتور.** با `grep` روی فایل هنوز دیده می‌شوند.

## چرا موتور اجرا ویرایش نشد

موتور `stripped` است و سورس آن در این مخزن وجود ندارد. رشته‌های داخلی فقط با
ویرایش hex قابل تغییرند، که offsetها را می‌شکند و فایل را خراب می‌کند. **این کار
انجام نشد و توصیه هم نمی‌شود** — MD5 بالا قابل تأیید است.

برای برندسازی کامل (شامل پنل داخلی و حذف کد لایسنس) باید از سورس آپ‌استریم build
بگیرید:

```bash
git clone https://github.com/musix/backhaul
```

سپس `cmd/api.go`، `cmd/license.go` و `cmd/heartbeat.go` را حذف کنید (توضیح در
بخش بعد)، رشته‌های برندینگ و `internal/web/sniffer.go` را ویرایش کنید، و با
`GOAMD64=v3` build بگیرید.

## کد لایسنس و telemetry

موتور اجرا این توابع و آدرس‌ها را در خود دارد:

```
cmd.checkLicense    cmd.runLicenseCheck    cmd.decryptWithAES
cmd.callAPI         cmd.getServerIP        cmd.heartbeat / runHeartbeat

https://license.p2p1shop.ir/
https://license1.rocektserver.com/
https://license2.rocektserver.com/
/license-validation2?server_ip=%s
heartbeat?server_ip=%s
```

یعنی نسخه‌ی اصلی **IP سرور را به سرورهای شخص سوم می‌فرستاده**. یادداشت patch
همراه موتور اجرا (اکنون در ابتدای [UPSTREAM-BACKHAUL.md](UPSTREAM-BACKHAUL.md))
ادعا می‌کند این رفتار غیرفعال شده. در تحلیل ایستا ارجاع مستقیمی به این آدرس‌ها
پیدا نشد که با ادعای patch سازگار است، **اما تحلیل ایستا قطعی نیست.**

**پیش از استفاده در production** روی یک VPS آزمایشی با `tcpdump` تأیید کنید که
اتصالی به این دامنه‌ها برقرار نمی‌شود:

```bash
tcpdump -n -i any 'port 443 or port 80' -A | grep -iE 'rocektserver|p2p1shop'
```

فیلتر برندینگ CLI اینجا کاری نمی‌کند: فقط متن خروجی را عوض می‌کند و روی رفتار
شبکه‌ی موتور اجرا هیچ اثری ندارد.

## لایسنس

پروژه‌ی آپ‌استریم تحت WTFPL v2 منتشر شده (فایل `LICENSE`) که هرگونه استفاده،
تغییر و توزیع را مجاز می‌کند. build «Premium» یک نسخه‌ی تجاری از همان سورس است
که توسط شخص ثالث patch شده — منشأ آن قابل تأیید نیست.
