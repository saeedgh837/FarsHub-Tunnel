# پنل وب تنظیم و راه‌اندازی تونل — پلن پیاده‌سازی

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** پنل وب موجود بتواند تونل را از سرور خام تا حالت زنده کانفیگ کند و بالا بیاورد، بدون اینکه CLI کارایی‌اش را از دست بدهد و بدون اینکه تونل زنده‌ی فعلی لحظه‌ای قطع شود.

**Architecture:** یک سرویس systemd تازه (`farshub-api`، Python از کتابخانه‌ی استاندارد) روی `127.0.0.1:2061` که هشت اندپوینت JSON می‌دهد و برای **هر** کار نیازمند root فقط `sudo farshub <زیردستور>` را با آرگومان ثابت صدا می‌زند — پس CLI تنها نویسنده و تنها خواننده‌ی کانفیگ می‌ماند و واگرایی پنل و CLI ساختاراً ناممکن است. nginx همان سایتی که `panel-up` می‌سازد یک `location /api/` تازه می‌گیرد، پس پنل و API زیر یک `auth_basic` می‌مانند. سمت مرورگر دو تب hash-routed اضافه می‌شود بدون فریم‌ورک، بدون build step، بدون CDN.

**Tech Stack:** POSIX `sh` (`bin/farshub`) · Python 3.8+ stdlib (`http.server`, `subprocess`, `json`) · nginx · systemd · ES modules خالص در مرورگر · تست: `sh` خالص + `unittest` + `node --test`

**Spec:** [docs/superpowers/specs/2026-09-06-web-config-panel-design.md](../specs/2026-09-06-web-config-panel-design.md)

## Global Constraints

- **`bin/farshub-core` هرگز تغییر نمی‌کند.** MD5 باید `2f86ffb6ab33de43abfc606e12a8d972` بماند.
- **بدون فریم‌ورک، بدون build step، بدون CDN.** هر چه در `web/` است باید مستقیم از فایل سیستم سرو شود.
- **بدون وابستگی نصبی.** Python فقط کتابخانه‌ی استاندارد؛ نه `pip install`، نه `jq`، نه `apache2-utils`.
- **همه‌ی رشته‌های کاربر در هر دو زبان.** کلیدهای نقطه‌دار تخت در `web/assets/js/i18n.js`، هم در بلوک `fa` و هم `en`.
- **`letter-spacing` فقط زیر `[data-locale='en']`.** فاصله‌ی حروف، فارسی را می‌شکند (`panel.css:166`).
- **`.gitattributes` خط را LF می‌کند.** یک CR در shebang یعنی `bad interpreter: /bin/sh^M` روی لینوکس.
- **`FARSHUB_*` تنها راه انزوا است.** هیچ مسیر یا نامی نباید هاردکد بماند که تست را به نصب زنده وصل کند.
- **ری‌استارت هرگز خودکار نیست.** ذخیره‌ی کانفیگ سرویس را ری‌استارت نمی‌کند؛ کاربر باید صریح بزند.
- **توکن یک‌طرفه است.** از سرور به مرورگر هیچ‌وقت نمی‌رود؛ `********` می‌رود.
- **رشته‌های خطای CLI فارسی‌اند و از `die` می‌آیند.** API آنها را دست‌نخورده در `detail` پاس می‌دهد؛ کد ماشینی در `error` می‌نشیند.
- **آرگومان هرگز از رشته ساخته نمی‌شود.** `subprocess` با آرایه، `shell=False`، بدون استثنا.

## چهار تصحیح روی اسپک

این چهار مورد از خواندن کد بیرون آمد، بعد از نوشتن اسپک. پلن نسخه‌ی درست را پیاده می‌کند و بخش ۹ اسپک را به‌روز می‌کند.

**۱. `NoNewPrivileges=yes` و `ProtectSystem=strict` روی یونیت API نمی‌آیند.** جدول امنیت اسپک هر دو را خواسته بود، ولی:

- `NoNewPrivileges=yes` اجرای setuid را می‌بندد و `sudo` setuid است — کل طرح روی `sudo farshub` سوار است، پس این تنظیم سرویس را از کار می‌انداخت.
- `ProtectSystem=strict` کل سلسله‌مراتب فایل را read-only می‌کند و این mount namespace به بچه‌های root هم ارث می‌رسد. یعنی `sudo farshub apply-config` نمی‌توانست در `/etc/farshub` بنویسد و `sudo farshub install` در `/usr/local`.

هیچ‌کدام هم در برابر تهدید واقعی چیزی اضافه نمی‌کردند: کاربر `farshub-api` با مجوزهای معمولی یونیکس هم نمی‌تواند `/etc/farshub` (root، `600`) یا `/usr/local` را بنویسد. مرز واقعی همان است که می‌ماند: کاربر بدون shell، sudoers با آرگومان ثابت، `PrivateTmp`، `ProtectHome`، `RestrictAddressFamilies`، `MemoryMax`، `TasksMax`.

**۲. نام یونیت هم مثل `SITE_NAME` هاردکد است.** `side_unit()` عیناً `farshub-server.service` را برمی‌گرداند. با `FARSHUB_UNIT_DIR` جدا، فایل یونیت جایی نوشته می‌شد که systemd نمی‌خواند، و `systemctl restart farshub-server` در تست **سرویس زنده** را ری‌استارت می‌کرد. پس `FARSHUB_UNIT_PREFIX` هم لازم است — بدون آن، انزوای بخش ۶ اسپک روی کاغذ است.

**۳. `sudo farshub install` از مسیر API کار نمی‌کرد.** `cmd_install` منبعش را از مخزنِ کنار اسکریپت پیدا می‌کند؛ بعد از نصب، اسکریپت در `/usr/local/bin` است و مخزنی کنارش نیست، پس `die 'farshub-core کنار این اسکریپت نیست.'`. برای اینکه ویزارد بتواند نصب کند، `install` باید `configs/` و `systemd/` را در `$STATE_DIR/payload` بگذارد و دفعه‌ی بعد از آنجا بخواند.

**۴. نام سرویس API هم باید پیشوند بگیرد.** یونیت `farshub-api.service`، فایل `/etc/sudoers.d/farshub-api` و اجرایی `$BIN_DIR/farshub-api` هر سه ثابت بودند. با دو نمونه‌ی جدا (که بخش ۹ اسپک لازم دارد) نمونه‌ی دوم یونیت و sudoers نمونه‌ی اول را بازنویسی می‌کرد، و بدتر، `api-down` روی یکی سرویس دیگری را می‌کشت. پس هر سه از `$UNIT_PREFIX` مشتق می‌شوند:

```sh
API_UNIT="$UNIT_PREFIX-api.service"
API_BIN="$BIN_DIR/$UNIT_PREFIX-api"
API_SUDOERS="/etc/sudoers.d/$UNIT_PREFIX-api"
```

پیش‌فرض `UNIT_PREFIX` همان `farshub` است، پس نام‌های نصب معمولی عوض نمی‌شوند.

سه پیامد جانبی که همین‌جا حل می‌شوند: `panel-up` باید حالت «هنوز سمتی نصب نیست» را تحمل کند (وگرنه `setup` روی سرور خام نمی‌تواند پنل را بالا بیاورد و ویزارد هرگز دیده نمی‌شود)، `panel-up` باید پورت پنل را از `$PANEL_STATE` پیش‌فرض بگیرد (وگرنه اجرای دوباره‌اش پنل را از پورت دلخواه به ۸۰۸۸ می‌برد)، و sudoers دو ورودی `panel-up server|client` می‌گیرد چون همان عملیاتی است که نصبِ سمت را «تمام» می‌کند.

---

## File Structure

| فایل | مسئولیت |
| --- | --- |
| `tests/lib.sh` | **ساخت** — assertion و fixture، POSIX sh، بدون وابستگی |
| `tests/run.sh` | **ساخت** — اجراکننده‌ی هر سه دسته تست (cli / api / web) |
| `tests/cli/test-env-isolation.sh` | **ساخت** — `FARSHUB_SITE_NAME`، `FARSHUB_UNIT_PREFIX`، payload |
| `tests/cli/test-apply-config.sh` | **ساخت** — allowlist، نوع، بازه، قالب، نوشتن اتمیک |
| `tests/cli/test-write-site.sh` | **ساخت** — خروجی nginx با و بدون `location /api/` |
| `tests/api/test_api.py` | **ساخت** — `handle()` با `run_cli` جعلی؛ بدون سوکت |
| `tests/web/config-schema.test.mjs` | **ساخت** — اعتبارسنجی سمت مرورگر |
| `bin/farshub-api` | **ساخت** — سرویس API؛ dispatch خالص + پوسته‌ی نازک HTTP |
| `systemd/farshub-api.service` | **ساخت** — یونیت سرویس API |
| `bin/farshub` | **تغییر** — `paths`، `apply-config`، `api-up/down`، `setup`، انزوای محیطی |
| `configs/api.sudoers` | **ساخت** — قالب sudoers که `api-up` نصبش می‌کند |
| `web/assets/js/config-schema.js` | **ساخت** — جدول کلیدها و اعتبارسنجی خالص، بدون DOM |
| `web/assets/js/api.js` | **ساخت** — کلاینت `/api/*` و `ApiError` |
| `web/assets/js/router.js` | **ساخت** — روتر hash برای دو تب |
| `web/assets/js/settings.js` | **ساخت** — تب تنظیمات: چهار کارت، ذخیره، preflight |
| `web/assets/js/wizard.js` | **ساخت** — ویزارد سه‌مرحله‌ای سرور خام |
| `web/assets/js/app.js` | **تغییر** — سوار کردن تب‌ها، توقف poll در تب تنظیمات |
| `web/assets/js/i18n.js` | **تغییر** — کلیدهای تازه در هر دو زبان + `tf()` |
| `web/index.html` | **تغییر** — نوار تب، بخش تنظیمات، بخش ویزارد |
| `web/assets/css/panel.css` | **تغییر** — تب، فرم، دکمه، سوییچ، دیالوگ، نوار هشدار، ویزارد |
| `web/devserver.py` | **تغییر** — mock هشت اندپوینت + `do_POST`/`do_PUT` |
| `docs/CLI.md` | **تغییر** — زیردستورهای تازه + جدول متغیرهای محیطی |
| `docs/PANEL.md` | **تغییر** — تب تنظیمات، سرویس API، مرزها |
| `README.md` | **تغییر** — راه‌اندازی یک‌خطی با `setup` |

---

## Task 1: هارنس تست و انزوای محیطی

بدون این تسک هیچ تست دیگری قابل اجرا نیست، و تست روی سرور زنده امن نیست. سه چیز هاردکد که باید محیطی شوند: نام سایت nginx، نام یونیت systemd، و منبع فایل‌های نصب.

**Files:**
- Create: `tests/lib.sh`, `tests/run.sh`, `tests/cli/test-env-isolation.sh`
- Modify: `bin/farshub` (`side_unit` خط ۶۷–۷۲، `SITE_NAME` خط ۶۱۸، `cmd_install` خط ۴۰۵–۵۱۱، dispatch خط ۱۰۳۴)
- Modify: `docs/CLI.md:193-206`

**Interfaces:**
- Consumes: چیزی از تسک قبلی نیست — اولین تسک است.
- Produces:
  - `tests/lib.sh` → متغیرهای `REPO`, `FARSHUB`, `PY`, `OUT`, `RC` و توابع `run "$@"`, `run_stdin DATA "$@"`, `fh ARGS...`, `fh_stdin DATA ARGS...`, `fixture [side] → dir`, `envrun DIR ARGS...`, `assert_eq NAME GOT WANT`, `assert_rc NAME WANT`, `assert_contains NAME HAYSTACK NEEDLE`, `assert_missing NAME HAYSTACK NEEDLE`, `assert_file NAME PATH`, `summary`
  - `bin/farshub` → `UNIT_PREFIX` (از `FARSHUB_UNIT_PREFIX`)، `SITE_NAME` (از `FARSHUB_SITE_NAME`)، `PAYLOAD_DIR="$STATE_DIR/payload"`، `API_STATE="$STATE_DIR/api.conf"`، توابع `find_payload() → dir`, `resolve_site_paths()` (تنظیم `SITE_FILE` و `SITE_LINK`), `guess_side_soft() → side|''`, `write_unit_env FILE SIDE`, و زیردستور `farshub paths [side]`
  - `tests/run.sh` → `sh tests/run.sh [all|cli|api|web]`

- [ ] **Step 1: `tests/lib.sh` را بساز**

```sh
# کتابخانه‌ی تست — POSIX sh، بدون وابستگی.
#
# هر فایل تست این را source می‌کند و در پایان summary صدا می‌زند.
# فایل‌های تست «set -e» نمی‌گذارند: run() عمداً کد خروج غیرصفر را می‌گیرد و در
# RC می‌گذارد، و با set -e همان‌جا کل تست می‌مرد.

REPO=${REPO:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
FARSHUB="$REPO/bin/farshub"

# روی ویندوز، python3 یک alias شکسته‌ی Microsoft Store است: در PATH هست ولی
# اجرا نمی‌شود. پس «وجود دارد یا نه» کافی نیست — باید واقعاً بالا بیاید.
py_bin() {
  for c in python3 python py; do
    command -v "$c" >/dev/null 2>&1 || continue
    if "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' \
         >/dev/null 2>&1; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}
PY=$(py_bin || true)

PASS=0
FAIL=0
NAME=$(basename -- "$0")

ok() {
  PASS=$((PASS + 1))
  printf '    ok   %s\n' "$1"
}

bad() {
  FAIL=$((FAIL + 1))
  printf '    FAIL %s\n' "$1" >&2
  [ $# -gt 1 ] && printf '         %s\n' "$2" >&2
  return 0
}

# دستور را اجرا می‌کند و خروجی ترکیبی را در OUT و کد خروج را در RC می‌گذارد.
run() { OUT=$("$@" 2>&1); RC=$?; return 0; }

run_stdin() {
  _in=$1
  shift
  OUT=$(printf '%s' "$_in" | "$@" 2>&1)
  RC=$?
  return 0
}

# اسکریپت را با «sh» صدا می‌زنیم نه مستقیم: روی ویندوز نه بیت اجرا معنا دارد
# نه shebang.
fh() { run sh "$FARSHUB" "$@"; }
fh_stdin() { _d=$1; shift; run_stdin "$_d" sh "$FARSHUB" "$@"; }

# اجرای farshub با همه‌ی FARSHUB_* روی یک fixture — همان چیزی که روی سرور
# زنده هم تست را منزوی می‌کند.
envrun() {
  _d=$1
  shift
  run env \
    FARSHUB_CONF_DIR="$_d/conf" \
    FARSHUB_LIBEXEC="$_d/libexec" \
    FARSHUB_BIN_DIR="$_d/bin" \
    FARSHUB_UNIT_DIR="$_d/units" \
    FARSHUB_LOG_DIR="$_d/log" \
    FARSHUB_STATE_DIR="$_d/state" \
    FARSHUB_UNIT_PREFIX=farshub-test \
    FARSHUB_SITE_NAME=farshub-test \
    sh "$FARSHUB" "$@"
}

assert_eq() { [ "$2" = "$3" ] && ok "$1" || bad "$1" "انتظار «$3»، آمد «$2»"; }
assert_rc() { [ "$RC" = "$2" ] && ok "$1" || bad "$1" "کد خروج $RC بود نه $2 — خروجی: $OUT"; }
assert_contains() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "«$3» نبود در: $2" ;; esac; }
assert_missing() { case "$2" in *"$3"*) bad "$1" "«$3» نباید باشد در: $2" ;; *) ok "$1" ;; esac; }
assert_file() { [ -f "$2" ] && ok "$1" || bad "$1" "فایل نیست: $2"; }

# یک نصب موقت. اگر سمتی بدهید کانفیگ پیش‌فرضش را هم می‌گذارد.
fixture() {
  d=$(mktemp -d)
  mkdir -p "$d/conf" "$d/state" "$d/log" "$d/units" "$d/libexec" "$d/bin"
  [ -n "${1:-}" ] && cp "$REPO/configs/$1.toml" "$d/conf/$1.toml"
  printf '%s\n' "$d"
}

summary() {
  printf '  %s — %s pass, %s fail\n' "$NAME" "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
```

- [ ] **Step 2: `tests/run.sh` را بساز**

```sh
#!/bin/sh
# اجراکننده‌ی تست‌ها. سه دسته، هر سه بدون وابستگی نصبی:
#   cli  تست‌های sh روی bin/farshub
#   api  unittest روی bin/farshub-api
#   web  node --test روی ماژول‌های web/assets/js
#
#   sh tests/run.sh            همه
#   sh tests/run.sh cli        فقط یک دسته
set -u

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export REPO
want=${1:-all}
rc=0

pick_py() {
  for c in python3 python py; do
    command -v "$c" >/dev/null 2>&1 || continue
    if "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' \
         >/dev/null 2>&1; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

if [ "$want" = all ] || [ "$want" = cli ]; then
  printf '\n== CLI ==\n'
  for t in "$REPO"/tests/cli/test-*.sh; do
    [ -f "$t" ] || continue
    sh "$t" || rc=1
  done
fi

if [ "$want" = all ] || [ "$want" = api ]; then
  printf '\n== API ==\n'
  py=$(pick_py || true)
  if [ -z "$py" ]; then
    printf '  رد شد — python3 پیدا نشد\n'
  else
    ( cd "$REPO" && "$py" -m unittest discover -s tests/api -t tests/api ) || rc=1
  fi
fi

if [ "$want" = all ] || [ "$want" = web ]; then
  printf '\n== WEB ==\n'
  if command -v node >/dev/null 2>&1; then
    ( cd "$REPO" && node --test tests/web/ ) || rc=1
  else
    printf '  رد شد — node پیدا نشد\n'
  fi
fi

printf '\n'
if [ "$rc" = 0 ]; then
  printf 'همه‌ی تست‌ها پاس شد.\n'
else
  printf 'تست شکست خورد.\n' >&2
fi
exit "$rc"
```

- [ ] **Step 3: تست شکست‌خورده‌ی انزوا را بنویس**

`tests/cli/test-env-isolation.sh`:

```sh
#!/bin/sh
# نام سایت nginx و نام یونیت systemd هم باید مثل بقیه‌ی FARSHUB_* قابل
# override باشند. بدون این، اجرای تست روی سرور زنده سایت و سرویس زنده را
# بازنویسی می‌کند — همان چیزی که بخش ۶ اسپک باید جلویش را بگیرد.
set -u
. "$(dirname -- "$0")/../lib.sh"

d=$(fixture)
trap 'rm -rf "$d"' EXIT

# ۱) paths پیش‌فرض
fh paths server
assert_rc 'paths بدون خطا' 0
assert_contains 'یونیت پیش‌فرض' "$OUT" 'unit=farshub-server.service'
assert_contains 'نام سایت پیش‌فرض' "$OUT" 'site_name=farshub-panel'

# ۲) paths با override — هیچ نامی نباید به نصب زنده اشاره کند
envrun "$d" paths server
assert_rc 'paths با override' 0
assert_contains 'یونیت جدا' "$OUT" 'unit=farshub-test-server.service'
assert_contains 'سایت جدا' "$OUT" 'site_name=farshub-test'
assert_contains 'کانفیگ جدا' "$OUT" "conf=$d/conf/server.toml"
assert_missing 'اشاره‌ای به یونیت زنده نیست' "$OUT" 'unit=farshub-server.service'
assert_missing 'اشاره‌ای به سایت زنده نیست' "$OUT" 'site_name=farshub-panel'

# ۳) install با override: فایل یونیت باید با نام prefix نوشته شود، و drop-in
#    محیطی داشته باشد وگرنه _exec سرویس کانفیگ اشتباه را برمی‌دارد.
envrun "$d" install server
assert_rc 'install با override' 0
assert_file 'یونیت با نام جدا نوشته شد' "$d/units/farshub-test-server.service"
assert_file 'drop-in محیطی نوشته شد' "$d/units/farshub-test-server.service.d/10-farshub-env.conf"
dropin=$(cat "$d/units/farshub-test-server.service.d/10-farshub-env.conf" 2>/dev/null || true)
assert_contains 'drop-in مسیر کانفیگ را می‌دهد' "$dropin" "Environment=FARSHUB_CONF_DIR=$d/conf"
assert_contains 'drop-in ExecStart را بازنویسی می‌کند' "$dropin" "ExecStart=$d/bin/farshub _exec server"

# ۴) payload: نصب سمت دوم باید بدون مخزن هم کار کند — API از /usr/local/bin
#    صدا می‌زند و آنجا مخزنی نیست.
assert_file 'payload کانفیگ‌ها' "$d/state/payload/configs/client.toml"
assert_file 'payload یونیت‌ها' "$d/state/payload/systemd/farshub-client.service"
rm -rf "$d/second"
mkdir -p "$d/second"
cp "$d/bin/farshub" "$d/second/farshub"     # نسخه‌ی نصب‌شده، بدون مخزن کنارش
run env \
  FARSHUB_CONF_DIR="$d/conf" FARSHUB_LIBEXEC="$d/libexec" \
  FARSHUB_BIN_DIR="$d/bin" FARSHUB_UNIT_DIR="$d/units" \
  FARSHUB_LOG_DIR="$d/log" FARSHUB_STATE_DIR="$d/state" \
  FARSHUB_UNIT_PREFIX=farshub-test \
  sh "$d/second/farshub" install client
assert_rc 'install سمت دوم بدون مخزن' 0
assert_file 'کانفیگ سمت دوم' "$d/conf/client.toml"

summary
```

- [ ] **Step 4: تست را اجرا کن و ببین شکست می‌خورد**

```bash
sh tests/run.sh cli
```

انتظار: `FAIL paths بدون خطا` — زیردستور `paths` وجود ندارد، `farshub` آن را به core پاس می‌دهد و core هم روی ویندوز نیست.

- [ ] **Step 5: انزوای نام‌ها را در `bin/farshub` پیاده کن**

`side_unit` (خط ۶۷) — prefix محیطی. بلافاصله بالای `side_conf` این را اضافه کن:

```sh
# نام یونیت هم مثل مسیرها باید قابل انزوا باشد، وگرنه تست روی سرور زنده
# «systemctl restart farshub-server» می‌زند و تونل واقعی را می‌خواباند.
UNIT_PREFIX="${FARSHUB_UNIT_PREFIX:-farshub}"
```

و بدنه‌ی `side_unit` را عوض کن:

```sh
side_unit() {
  case "$1" in
    server|s) printf '%s-server.service\n' "$UNIT_PREFIX" ;;
    client|c) printf '%s-client.service\n' "$UNIT_PREFIX" ;;
    *) die "سمت نامعتبر: «$1» (server یا client)" ;;
  esac
}
```

بعد از `guess_side`، نسخه‌ی بی‌مرگ آن را اضافه کن — `setup` و `panel-up` روی سرور خام باید بتوانند «هیچ سمتی نصب نیست» را تحمل کنند:

```sh
# مثل guess_side ولی وقتی هیچ سمتی نصب نیست یا هر دو نصب‌اند، فقط ساکت
# چیزی برنمی‌گرداند. panel-up روی سرور خام به این نیاز دارد.
guess_side_soft() {
  has_s=0; has_c=0
  [ -f "$CONF_DIR/server.toml" ] && has_s=1
  [ -f "$CONF_DIR/client.toml" ] && has_c=1
  if [ "$has_s" = 1 ] && [ "$has_c" = 0 ]; then printf 'server\n'; fi
  if [ "$has_c" = 1 ] && [ "$has_s" = 0 ]; then printf 'client\n'; fi
  return 0
}
```

خط ۶۱۸ (`SITE_NAME='farshub-panel'`) را به این سه خط عوض کن:

```sh
PANEL_STATE="$STATE_DIR/panel.conf"
API_STATE="$STATE_DIR/api.conf"
HTPASSWD_FILE="${FARSHUB_HTPASSWD:-/etc/nginx/farshub.htpasswd}"
SITE_NAME="${FARSHUB_SITE_NAME:-farshub-panel}"
PAYLOAD_DIR="$STATE_DIR/payload"
```

- [ ] **Step 6: کشف مسیر سایت nginx را از `cmd_panel_up` بیرون بکش**

امروز این تشخیص داخل `cmd_panel_up` است و `cmd_panel_down` فهرست کاندیدهای خودش را جدا هاردکد کرده. یک تابع، دو مصرف‌کننده، و `paths` هم می‌تواند گزارشش کند. بلافاصله بعد از `have_ipv6` اضافه کن:

```sh
# دبیان/اوبونتو sites-available دارند، رد‌هت conf.d. هر دو را پوشش می‌دهیم و
# نتیجه را در SITE_FILE و SITE_LINK می‌گذاریم (SITE_LINK فقط در حالت اول).
resolve_site_paths() {
  if [ -d /etc/nginx/sites-available ] && [ -d /etc/nginx/sites-enabled ]; then
    SITE_FILE="/etc/nginx/sites-available/$SITE_NAME"
    SITE_LINK="/etc/nginx/sites-enabled/$SITE_NAME"
  else
    SITE_FILE="/etc/nginx/conf.d/$SITE_NAME.conf"
    SITE_LINK=''
  fi
}
```

در `cmd_panel_up` هر جا مسیر سایت را inline تشخیص می‌دهد، جایش `resolve_site_paths; site=$SITE_FILE; link=$SITE_LINK` بگذار. منطق را عوض نکن — فقط جابه‌جا.

- [ ] **Step 7: payload و drop-in محیطی را به `cmd_install` اضافه کن**

بالای `cmd_install` این را اضافه کن:

```sh
# منبع فایل‌های نصب: مخزن اگر کنار اسکریپت باشد، وگرنه نسخه‌ای که نصب قبلی
# در $PAYLOAD_DIR گذاشته. بدون این، «sudo farshub install client» از مسیر
# API شکست می‌خورد — آن‌جا اسکریپت در /usr/local/bin است و مخزنی کنارش نیست.
find_payload() {
  if [ -f "$self_dir/../configs/server.toml" ]; then
    (CDPATH= cd -- "$self_dir/.." && pwd)
  elif [ -f "$PAYLOAD_DIR/configs/server.toml" ]; then
    printf '%s\n' "$PAYLOAD_DIR"
  else
    die "فایل‌های نصب پیدا نشد — نه کنار اسکریپت، نه در $PAYLOAD_DIR."
  fi
}

# وقتی مسیرها یا نام یونیت override شده‌اند، سرویس باید همان محیط را ببیند
# وگرنه _exec کانفیگ پیش‌فرض را برمی‌دارد.
write_unit_env() {                      # $1=مسیر drop-in  $2=سمت
  mkdir -p "$(dirname -- "$1")"
  cat >"$1" <<EOF
# ساخته‌ی «farshub install» — چون مسیرهای FARSHUB_* پیش‌فرض نبودند.
[Service]
Environment=FARSHUB_CONF_DIR=$CONF_DIR
Environment=FARSHUB_LIBEXEC=$LIBEXEC
Environment=FARSHUB_BIN_DIR=$BIN_DIR
Environment=FARSHUB_UNIT_DIR=$UNIT_DIR
Environment=FARSHUB_LOG_DIR=$LOG_DIR
Environment=FARSHUB_STATE_DIR=$STATE_DIR
Environment=FARSHUB_UNIT_PREFIX=$UNIT_PREFIX
ExecStart=
ExecStart=$BIN_DIR/farshub _exec $2
EOF
  chmod 644 "$1"
}
```

در بدنه‌ی `cmd_install`، بلوک `src`/`repo` را با `repo=$(find_payload)` عوض کن و `src` را همان‌طور برای `farshub-core` نگه دار (core کنار اسکریپت است یا در `$LIBEXEC`). بعد از کپی `web/`، payload را بنویس:

```sh
  # payload تا نصب سمت دوم بی‌مخزن هم کار کند.
  install -d -m755 "$PAYLOAD_DIR/configs" "$PAYLOAD_DIR/systemd"
  cp "$repo/configs/server.toml" "$repo/configs/client.toml" "$PAYLOAD_DIR/configs/"
  cp "$repo/systemd/farshub-server.service" "$repo/systemd/farshub-client.service" \
     "$PAYLOAD_DIR/systemd/"
  chmod -R u=rwX,go=rX "$PAYLOAD_DIR"
  say "  منبع   → $PAYLOAD_DIR"
```

و بلوک یونیت را عوض کن — نوشتن فایل دیگر به systemd گره نمی‌خورد، فقط `daemon-reload`:

```sh
  unit=$(side_unit "$side")
  install -Dm644 "$repo/systemd/farshub-$side.service" "$UNIT_DIR/$unit"
  say "  سرویس  → $UNIT_DIR/$unit"
  if [ "$UNIT_PREFIX" != 'farshub' ] || [ "$CONF_DIR" != '/etc/farshub' ] ||
     [ "$BIN_DIR" != '/usr/local/bin' ] || [ "$STATE_DIR" != '/var/lib/farshub' ]; then
    write_unit_env "$UNIT_DIR/$unit.d/10-farshub-env.conf" "$side"
    say "  محیط   → $UNIT_DIR/$unit.d/10-farshub-env.conf"
  fi
  if have_systemd; then
    systemctl daemon-reload
  else
    say '  سرویس  → daemon-reload رد شد (systemd نیست)'
  fi
```

- [ ] **Step 8: زیردستور `paths` را اضافه کن**

بلافاصله بالای `cmd_panel_meta`:

```sh
# «این نصب کجاست؟» — همان سؤالی که در پشتیبانی مرتب پرسیده می‌شود، و تنها
# راه دیدن اثر FARSHUB_* بدون root و بدون systemd.
cmd_paths() {
  side=${1:-}
  [ -n "$side" ] || side=$(guess_side_soft)
  [ -n "$side" ] || side=server
  case "$side" in server|s) side=server ;; client|c) side=client ;;
    *) die "سمت نامعتبر: «$side»" ;; esac
  resolve_site_paths
  unit=$(side_unit "$side")
  printf 'side=%s\n'        "$side"
  printf 'conf=%s\n'        "$(side_conf "$side")"
  printf 'unit=%s\n'        "$unit"
  printf 'unit_file=%s\n'   "$UNIT_DIR/$unit"
  printf 'dropin_dir=%s\n'  "$UNIT_DIR/$unit.d"
  printf 'site_name=%s\n'   "$SITE_NAME"
  printf 'site=%s\n'        "$SITE_FILE"
  printf 'site_link=%s\n'   "$SITE_LINK"
  printf 'htpasswd=%s\n'    "$HTPASSWD_FILE"
  printf 'panel_state=%s\n' "$PANEL_STATE"
  printf 'api_state=%s\n'   "$API_STATE"
  printf 'web=%s\n'         "$STATE_DIR/web"
  printf 'payload=%s\n'     "$PAYLOAD_DIR"
  printf 'libexec=%s\n'     "$LIBEXEC"
  printf 'log=%s\n'         "$LOG_DIR"
  printf 'bin=%s\n'         "$BIN_DIR"
}
```

در `case` انتهای فایل، بعد از خط `panel-meta`:

```sh
  paths)                   cmd_paths "$@" ;;
```

و در `cmd_help`، در فهرست «دستورها:» بعد از `panel-meta`:

```sh
  say '  paths [سمت]              مسیرها و نام‌های این نصب'
```

- [ ] **Step 9: تست را اجرا کن و ببین پاس می‌شود**

```bash
sh tests/run.sh cli
```

انتظار: PASS برای هر ۱۴ assertion؛ `0 fail`.

- [ ] **Step 10: جدول متغیرهای محیطی `docs/CLI.md` را کامل کن**

در جدول انتهای فایل (خط ۱۹۳–۲۰۶) سه ردیف اضافه کن:

```markdown
| `FARSHUB_UNIT_PREFIX` | `farshub` | پیشوند نام یونیت systemd — `farshub-server.service` |
| `FARSHUB_SITE_NAME` | `farshub-panel` | نام سایت nginx پنل |
| `FARSHUB_HTPASSWD` | `/etc/nginx/farshub.htpasswd` | فایل رمز پنل |
```

و زیر جدول این پاراگراف:

```markdown
سه تای آخر برای **انزوا** هستند. با آنها می‌توان یک نصب کامل و جدا روی همان
ماشین بالا آورد بدون اینکه نصب زنده لمس شود — نه سایت nginx‌اش بازنویسی شود و
نه `systemctl restart` سرویس زنده را بگیرد. `farshub paths` نشان می‌دهد هر
override به چه مسیری رسیده است:

    FARSHUB_CONF_DIR=/opt/fh-test/conf FARSHUB_UNIT_PREFIX=farshub-test \
      farshub paths server
```

- [ ] **Step 11: commit**

```bash
git add tests bin/farshub docs/CLI.md
git commit -m "تست: هارنس بدون وابستگی، و انزوای کامل نام یونیت و سایت nginx"
```

---

## Task 2: `apply-config` — اعتبارسنجی و نوشتن اتمیک

قلب امنیتی طرح. موتور اجرا حالت اعتبارسنجی ندارد، پس هر چه اینجا رد نشود روی دیسک می‌نشیند و تونل را می‌خواباند. فهرست کلیدها از `docs/UPSTREAM-BACKHAUL.md` می‌آید و بسته است.

**Files:**
- Create: `tests/cli/test-apply-config.sh`
- Modify: `bin/farshub` (کنار `set_conf_val` خط ۶۵۶؛ dispatch؛ `cmd_help`؛ `cmd_config` خط ۳۸۲)
- Modify: `docs/CLI.md`

**Interfaces:**
- Consumes: از تسک ۱ → `tests/lib.sh` (`fh_stdin`, `fixture`, `assert_*`), `side_conf`, `set_conf_val`, `need_write`, `die`
- Produces:
  - `farshub apply-config <server|client>` — JSON یا خطوط `key=value` از stdin؛ stdout یک خط به‌ازای هر کلید: `changed <key>` یا `unchanged <key>`؛ کد خروج `0` موفق، `1` خطای اعتبارسنجی (پیام فارسی روی stderr)، `2` خطای استفاده
  - توابع sh: `valid_int VALUE MIN MAX`, `valid_enum VALUE LIST`, `valid_addr VALUE`, `valid_path VALUE`, `valid_ipv4 VALUE`, `valid_token VALUE`, `valid_port_row VALUE`, `key_spec SIDE KEY → "type min max"`، `set_conf_ports FILE ROWS...`
  - `cmd_config` دیگر `CHANGE_ME` را ماسک نمی‌کند (API از همین سیگنال برای preflight استفاده می‌کند)

- [ ] **Step 1: تست شکست‌خورده را بنویس**

`tests/cli/test-apply-config.sh`:

```sh
#!/bin/sh
# apply-config تنها نویسنده‌ی کانفیگ است، پس تنها جایی است که می‌تواند جلوی
# مقدار خراب را بگیرد — موتور اجرا حالت اعتبارسنجی ندارد.
set -u
. "$(dirname -- "$0")/../lib.sh"

srv=$(fixture server)
cli=$(fixture client)
trap 'rm -rf "$srv" "$cli"' EXIT
S="$srv/conf/server.toml"
C="$cli/conf/client.toml"

sfh() { _d=$1; shift; fh_stdin "$1" env FARSHUB_CONF_DIR="$_d/conf" sh "$FARSHUB" apply-config "$2"; }

# --- پذیرش مقدار درست ---------------------------------------------------
run_stdin '{"transport":"wssmux","keepalive_period":90}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'JSON درست پذیرفته شد' 0
assert_contains 'transport عوض شد' "$OUT" 'changed transport'
assert_contains 'keepalive عوض شد' "$OUT" 'changed keepalive_period'
assert_contains 'مقدار نوشته شد' "$(cat "$S")" 'transport = "wssmux"'
assert_contains 'عدد بدون گیومه' "$(cat "$S")" 'keepalive_period = 90'
assert_contains 'کامنت انتهای خط ماند' "$(cat "$S")" 'keepalive_period = 90'
assert_file 'پشتیبان ساخته شد' "$S.bak"

# مقدار تکراری = unchanged، نه changed
run_stdin '{"transport":"wssmux"}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_contains 'مقدار یکسان unchanged است' "$OUT" 'unchanged transport'

# --- خطوط key=value، برای اسکریپت‌نویسی بدون python ---------------------
run_stdin 'log_level=debug
nodelay=false
' env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'خطوط key=value' 0
assert_contains 'رشته با گیومه' "$(cat "$S")" 'log_level = "debug"'
assert_contains 'بولین بدون گیومه' "$(cat "$S")" 'nodelay = false'

# --- رد کردن ------------------------------------------------------------
before=$(cat "$S")

run_stdin '{"transport":"quic"}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'transport ناشناس رد شد' 1
assert_contains 'پیام transport' "$OUT" 'transport'

run_stdin '{"bogus_key":1}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'کلید ناشناس رد شد' 1

run_stdin '{"heartbeat":0}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'عدد بیرون بازه رد شد' 1

run_stdin '{"nodelay":"yes"}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'بولین غیر true/false رد شد' 1

run_stdin '{"token":"short"}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'توکن کوتاه رد شد' 1

run_stdin '{"token":"CHANGE_ME_CHANGE_ME_CHANGE_ME_1234"}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'توکن با نویسه‌ی مجاز پذیرفته شد' 0

run_stdin '{"bind_addr":"0.0.0.0:99999"}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'پورت بیرون بازه رد شد' 1

run_stdin '{"bind_addr":"0.0.0.0:3080\"; rm -rf /"}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'نویسه‌ی خطرناک رد شد' 1

run_stdin '{"remote_addr":"1.2.3.4:3080"}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'کلید سمت مقابل رد شد' 1

# هیچ‌کدام از ردها نباید فایل را دست زده باشند
assert_eq 'فایل پس از ردها دست‌نخورده' "$(cat "$S")" "$before"

# --- ports --------------------------------------------------------------
run_stdin 'ports+=443
ports+=8443=443
ports+=2000-2100
ports+=127.0.0.2:443=1.1.1.1:5201
' env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'ردیف‌های معتبر ports' 0
body=$(cat "$S")
assert_contains 'ردیف ساده' "$body" '"443",'
assert_contains 'ردیف نگاشت' "$body" '"8443=443",'
assert_contains 'ردیف بازه' "$body" '"2000-2100",'
assert_contains 'ردیف کامل' "$body" '"127.0.0.2:443=1.1.1.1:5201",'
assert_contains 'کامنت نمونه‌ها ماند' "$body" '# نمونه'

run_stdin 'ports+=99999' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'پورت بیرون بازه در ردیف' 1

run_stdin 'ports+=2100-2000' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'بازه‌ی برعکس' 1

run_stdin 'ports=' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'خالی کردن ports' 0
assert_contains 'ports خالی شد' "$(cat "$S")" 'ports = ['

# --- سمت کلاینت ---------------------------------------------------------
run_stdin '{"remote_addr":"1.2.3.4:3080","connection_pool":16}' \
  env FARSHUB_CONF_DIR="$cli/conf" sh "$FARSHUB" apply-config client
assert_rc 'کلاینت پذیرفت' 0
assert_contains 'remote_addr نوشته شد' "$(cat "$C")" 'remote_addr = "1.2.3.4:3080"'

run_stdin 'ports+=443' \
  env FARSHUB_CONF_DIR="$cli/conf" sh "$FARSHUB" apply-config client
assert_rc 'کلاینت ports ندارد' 1

run_stdin '{"remote_addr":"SERVER_IP:3080"}' \
  env FARSHUB_CONF_DIR="$cli/conf" sh "$FARSHUB" apply-config client
assert_rc 'جای‌نگهدار remote_addr رد شد' 1

# --- استفاده ------------------------------------------------------------
run_stdin '{}' env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config
assert_rc 'بدون سمت' 2

summary
```

- [ ] **Step 2: تست را اجرا کن و ببین شکست می‌خورد**

```bash
sh tests/cli/test-apply-config.sh
```

انتظار: همه FAIL — زیردستور `apply-config` وجود ندارد.

- [ ] **Step 3: اعتبارسنج‌ها را بنویس**

بلافاصله بعد از `set_conf_val` (خط ۶۵۶ به بعد) اضافه کن:

```sh
# ---------------------------------------------------- اعتبارسنجی کانفیگ --
# فهرست کلیدها بسته است: در موتور کامپایل شده‌اند و عوض نمی‌شوند
# (docs/UPSTREAM-BACKHAUL.md). هر کلید یک نوع و یک بازه دارد.
#
# چرا این‌قدر سخت‌گیر: مقدار مستقیم داخل الگوی sed می‌نشیند، پس مجموعه‌ی
# نویسه‌های هر نوع طوری بسته شده که «\» و «&» و «|» و گیومه هیچ‌وقت رد نشوند.
# تزریق sed اینجا با ساختار غیرممکن است، نه با escape کردن.

TRANSPORTS='tcp tcpmux ws wss wsmux wssmux udp'
LOG_LEVELS='panic fatal error warn info debug trace'

valid_int() {                           # $1=مقدار $2=کمینه $3=بیشینه
  case $1 in ''|*[!0-9]*) return 1 ;; esac
  [ ${#1} -le 10 ] || return 1
  [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]
}

valid_enum() {                          # $1=مقدار $2=فهرست جدا با فاصله
  for v in $2; do [ "$1" = "$v" ] && return 0; done
  return 1
}

valid_bool() { [ "$1" = true ] || [ "$1" = false ]; }

valid_token() {
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9._~-]{32,256}$'
}

valid_path() {
  [ -z "$1" ] && return 0             # "" یعنی تنظیم‌نشده، مجاز است
  printf '%s' "$1" | grep -Eq '^/[A-Za-z0-9._/-]{1,255}$'
}

valid_ipv4() {
  printf '%s' "$1" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' || return 1
  for o in $(printf '%s' "$1" | tr '.' ' '); do
    [ "$o" -le 255 ] || return 1
  done
  return 0
}

valid_addr() {                          # host:port — host می‌تواند خالی باشد
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9_.:-]{0,253}:[0-9]{1,5}$' || return 1
  valid_int "${1##*:}" 1 65535
}

# ردیف ports:  [bindip:]port[-port][= یا :][remoteip:]port
valid_port_row() {
  printf '%s' "$1" | grep -Eq \
    '^([0-9]{1,3}(\.[0-9]{1,3}){3}:)?[0-9]{1,5}(-[0-9]{1,5})?([=:]([0-9]{1,3}(\.[0-9]{1,3}){3}:)?[0-9]{1,5})?$' ||
    return 1
  # اکتت‌های IP جدا سنجیده می‌شوند، چون regex بالا ۹۹۹ را هم می‌پذیرد
  for ip in $(printf '%s' "$1" | grep -Eo '[0-9]{1,3}(\.[0-9]{1,3}){3}'); do
    valid_ipv4 "$ip" || return 1
  done
  # هر عددی که جزء IP نیست باید پورت معتبر باشد
  rest=$(printf '%s' "$1" | sed -E 's/[0-9]{1,3}(\.[0-9]{1,3}){3}//g')
  for p in $(printf '%s' "$rest" | tr -c '0-9' ' '); do
    valid_int "$p" 1 65535 || return 1
  done
  case $1 in
    *-*)
      lo=${1%%-*}; lo=${lo##*:}
      hi=${1#*-}; hi=${hi%%[=:]*}
      [ "$lo" -le "$hi" ] || return 1
      ;;
  esac
  return 0
}

# نوع و بازه‌ی هر کلید. خروجی: «نوع کمینه بیشینه» یا خالی اگر کلید برای این
# سمت وجود ندارد. مقادیر از docs/UPSTREAM-BACKHAUL.md آمده‌اند.
key_spec() {                            # $1=سمت  $2=کلید
  case "$2" in
    # هر دو سمت
    transport)         printf 'enum\n' ;;
    token)             printf 'token\n' ;;
    keepalive_period)  printf 'int 1 3600\n' ;;
    nodelay)           printf 'bool\n' ;;
    sniffer)           printf 'bool\n' ;;
    sniffer_log)       printf 'path\n' ;;
    web_port)          printf 'int 0 65535\n' ;;
    log_level)         printf 'level\n' ;;
    pprof)             printf 'bool\n' ;;
    mux_version)       printf 'int 1 2\n' ;;
    mux_framesize)     printf 'int 4096 1048576\n' ;;
    mux_recievebuffer) printf 'int 65536 67108864\n' ;;
    mux_streambuffer)  printf 'int 16384 16777216\n' ;;
    tls_cert)          printf 'path\n' ;;
    tls_key)           printf 'path\n' ;;
    # فقط سرور
    bind_addr)         [ "$1" = server ] && printf 'addr\n' ;;
    ports)             [ "$1" = server ] && printf 'ports\n' ;;
    heartbeat)         [ "$1" = server ] && printf 'int 1 300\n' ;;
    channel_size)      [ "$1" = server ] && printf 'int 64 65536\n' ;;
    accept_udp)        [ "$1" = server ] && printf 'bool\n' ;;
    mux_con)           [ "$1" = server ] && printf 'int 1 64\n' ;;
    # فقط کلاینت
    remote_addr)       [ "$1" = client ] && printf 'remote\n' ;;
    edge_ip)           [ "$1" = client ] && printf 'ip\n' ;;
    connection_pool)   [ "$1" = client ] && printf 'int 1 1024\n' ;;
    aggressive_pool)   [ "$1" = client ] && printf 'bool\n' ;;
    retry_interval)    [ "$1" = client ] && printf 'int 1 300\n' ;;
    dial_timeout)      [ "$1" = client ] && printf 'int 1 300\n' ;;
  esac
  return 0
}

# مقدار را می‌سنجد و شکل TOML‌اش را چاپ می‌کند (رشته‌ها با گیومه). خطا ⇒ die.
toml_value() {                          # $1=سمت  $2=کلید  $3=مقدار
  spec=$(key_spec "$1" "$2")
  [ -n "$spec" ] || die "کلید ناشناس یا مربوط به سمت دیگر: «$2»"
  # shellcheck disable=SC2086
  set -- "$1" "$2" "$3" $spec
  case $4 in
    enum)  valid_enum "$3" "$TRANSPORTS" || die "transport نامعتبر: «$3» (یکی از: $TRANSPORTS)"
           printf '"%s"\n' "$3" ;;
    level) valid_enum "$3" "$LOG_LEVELS" || die "log_level نامعتبر: «$3» (یکی از: $LOG_LEVELS)"
           printf '"%s"\n' "$3" ;;
    token) valid_token "$3" || die 'توکن باید ۳۲ تا ۲۵۶ نویسه از [A-Za-z0-9._~-] باشد.'
           printf '"%s"\n' "$3" ;;
    bool)  valid_bool "$3" || die "«$2» باید true یا false باشد، نه «$3»"
           printf '%s\n' "$3" ;;
    int)   valid_int "$3" "$5" "$6" || die "«$2» باید عددی بین $5 و $6 باشد، نه «$3»"
           printf '%s\n' "$3" ;;
    path)  valid_path "$3" || die "«$2» باید مسیر مطلق بدون فاصله باشد: «$3»"
           printf '"%s"\n' "$3" ;;
    ip)    [ -z "$3" ] || valid_ipv4 "$3" || die "«$2» باید IPv4 باشد: «$3»"
           printf '"%s"\n' "$3" ;;
    addr)  valid_addr "$3" || die "«$2» باید host:port با پورت ۱ تا ۶۵۵۳۵ باشد: «$3»"
           printf '"%s"\n' "$3" ;;
    remote)
           valid_addr "$3" || die "«$2» باید host:port با پورت ۱ تا ۶۵۵۳۵ باشد: «$3»"
           case $3 in
             :*|SERVER_IP:*) die 'remote_addr باید نشانی واقعی سرور باشد، نه جای‌نگهدار.' ;;
           esac
           printf '"%s"\n' "$3" ;;
    *)     die "نوع ناشناخته برای «$2»" ;;
  esac
}
```

- [ ] **Step 4: نویسنده‌ی `ports` را بنویس**

بلافاصله بعد از بلوک بالا:

```sh
# جایگزینی کل بلوک ports. کامنت‌های داخلش (نمونه‌های کانفیگ ارسالی) نگه
# داشته می‌شوند — مستنداتی هستند که کاربر بعداً لازمش دارد.
set_conf_ports() {                      # $1=فایل  $2..=ردیف‌ها
  f=$1
  shift
  keep=$(sed -n '/^[[:space:]]*ports[[:space:]]*=[[:space:]]*\[/,/\]/p' "$f" 2>/dev/null |
           grep -E '^[[:space:]]*#' || true)
  rows=''
  for r in "$@"; do rows="$rows    \"$r\",
"; done
  if [ -z "$rows" ] && [ -z "$keep" ]; then
    block='ports = [ ]
'
  else
    block="ports = [
${keep:+$keep
}$rows]
"
  fi
  awk -v block="$block" '
    BEGIN { done = 0; inside = 0 }
    !done && !inside && /^[ \t]*ports[ \t]*=[ \t]*\[/ {
      printf "%s", block
      if ($0 ~ /\]/) { done = 1; next }
      inside = 1
      next
    }
    inside { if ($0 ~ /\]/) { inside = 0; done = 1 } ; next }
    { print }
    END { if (!done) printf "%s", block }
  ' "$f" >"$f.ports.$$" && mv "$f.ports.$$" "$f"
}
```

- [ ] **Step 5: `cmd_apply_config` را بنویس**

بلافاصله بعد از `set_conf_ports`:

```sh
# --------------------------------------------------------- apply-config --
# تنها نویسنده‌ی کانفیگ. دو پاس: اول همه چیز سنجیده می‌شود، بعد نوشته —
# پس کانفیگ نیم‌معتبر هرگز روی دیسک نمی‌رود. جایگزینی با mv در همان
# filesystem اتمیک است.
cmd_apply_config() {
  side=${1:-}
  [ -n "$side" ] || die 'سمت را بگویید: farshub apply-config server|client' 2
  case "$side" in server|s) side=server ;; client|c) side=client ;;
    *) die "سمت نامعتبر: «$side»" 2 ;; esac
  conf=$(side_conf "$side")
  [ -f "$conf" ] || die "کانفیگ نیست: $conf — اول «farshub install $side»."
  need_write "$CONF_DIR"

  raw=$(cat)
  # JSON یا خطوط key=value. JSON را python به خطوط تبدیل می‌کند؛ خودِ CLI
  # وابستگی نمی‌گیرد، چون شکل خطی بدون python کار می‌کند.
  case $raw in
    [[:space:]]*\{*|\{*)
      py=''
      for c in python3 python; do command -v "$c" >/dev/null 2>&1 && { py=$c; break; }; done
      [ -n "$py" ] ||
        die 'JSON خواندن python3 می‌خواهد. شکل بدون وابستگی: خطوط «کلید=مقدار».'
      lines=$(printf '%s' "$raw" | "$py" -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError as e:
    sys.exit("JSON نامعتبر: %s" % e)
if not isinstance(d, dict):
    sys.exit("JSON باید یک شیء باشد.")
out = []
for k, v in d.items():
    if isinstance(v, list):
        if not v:
            out.append("%s=" % k)
        for item in v:
            out.append("%s+=%s" % (k, item))
    elif isinstance(v, bool):
        out.append("%s=%s" % (k, "true" if v else "false"))
    elif v is None:
        out.append("%s=" % k)
    else:
        out.append("%s=%s" % (k, v))
sys.stdout.write("\n".join(out))
') || die "$lines"
      ;;
    *) lines=$raw ;;
  esac

  # ------- پاس یکم: سنجیدن. هیچ نوشتنی در این پاس نیست.
  pending=''                            # «کلید<TAB>مقدارTOML» به‌ازای هر خط
  rows=''                               # ردیف‌های ports
  has_ports=0
  printf '%s\n' "$lines" | tr -d '\r' >"$conf.in.$$"
  while IFS= read -r line; do
    case $line in ''|'#'*) continue ;; esac
    case $line in
      *'+='*)
        k=${line%%+=*}; v=${line#*+=}
        [ "$k" = ports ] || die "«+=» فقط برای ports است، نه «$k»"
        [ -n "$(key_spec "$side" ports)" ] || die 'سمت کلاینت کلید ports ندارد.'
        valid_port_row "$v" || die "ردیف ports نامعتبر: «$v»"
        rows="$rows$v
"
        has_ports=1
        ;;
      *'='*)
        k=${line%%=*}; v=${line#*=}
        case $k in ''|*[!a-z_]*) die "نام کلید نامعتبر: «$k»" ;; esac
        if [ "$k" = ports ]; then
          [ -n "$(key_spec "$side" ports)" ] || die 'سمت کلاینت کلید ports ندارد.'
          has_ports=1                   # «ports=» یعنی خالی کن
        else
          tv=$(toml_value "$side" "$k" "$v")
          pending="$pending$k	$tv
"
        fi
        ;;
      *) die "خط نامعتبر (شکل «کلید=مقدار»): «$line»" ;;
    esac
  done <"$conf.in.$$"
  rm -f "$conf.in.$$"

  [ -n "$pending" ] || [ "$has_ports" = 1 ] || die 'چیزی برای نوشتن نبود.'

  # ------- پاس دوم: نوشتن روی نسخه‌ی موقت
  tmp="$conf.new.$$"
  cp "$conf" "$tmp"
  chmod 600 "$tmp"
  report=''
  printf '%s' "$pending" | while IFS='	' read -r k tv; do
    [ -n "$k" ] || continue
    old=$(sed -n "s/^[[:space:]]*$k[[:space:]]*=[[:space:]]*//p" "$tmp" |
            sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//' | head -n1)
    if [ "$old" = "$tv" ]; then printf 'unchanged %s\n' "$k"
    else printf 'changed %s\n' "$k"; fi
  done >"$conf.rep.$$"
  printf '%s' "$pending" | while IFS='	' read -r k tv; do
    [ -n "$k" ] || continue
    set_conf_val "$tmp" "$k" "$tv"
  done
  if [ "$has_ports" = 1 ]; then
    old_ports=$(sed -n '/^[[:space:]]*ports[[:space:]]*=[[:space:]]*\[/,/\]/p' "$tmp")
    # shellcheck disable=SC2086
    if [ -z "$rows" ]; then set_conf_ports "$tmp"
    else
      saved_ifs=$IFS; IFS='
'; set -f
      # shellcheck disable=SC2086
      set -- $rows
      IFS=$saved_ifs; set +f
      set_conf_ports "$tmp" "$@"
    fi
    new_ports=$(sed -n '/^[[:space:]]*ports[[:space:]]*=[[:space:]]*\[/,/\]/p' "$tmp")
    if [ "$old_ports" = "$new_ports" ]; then printf 'unchanged ports\n' >>"$conf.rep.$$"
    else printf 'changed ports\n' >>"$conf.rep.$$"; fi
  fi

  # ------- جایگزینی اتمیک، با پشتیبان
  cp "$conf" "$conf.bak"
  chmod 600 "$conf.bak"
  mv "$tmp" "$conf"
  cat "$conf.rep.$$"
  rm -f "$conf.rep.$$"
}
```

- [ ] **Step 6: `cmd_config` را طوری کن که `CHANGE_ME` را ماسک نکند**

خط ۳۸۲ به بعد. `sed` ماسک را با این عوض کن — توکن پیش‌فرض راز نیست، جای‌نگهدار است، و پنهان کردنش هم انسان و هم API را از دیدن «هنوز تنظیم نشده» محروم می‌کند:

```sh
  # توکن ماسک می‌شود، ولی جای‌نگهدار CHANGE_ME نه: راز نیست، و دیدنش تنها
  # راهی است که پنل بفهمد توکن هنوز تنظیم نشده (توکن واقعی هیچ‌وقت بیرون
  # نمی‌رود، پس طولش هم قابل سنجش نیست).
  sed 's/^\([[:space:]]*token[[:space:]]*=[[:space:]]*\)"\(CHANGE_ME\)"/\1"\2"/
       s/^\([[:space:]]*token[[:space:]]*=[[:space:]]*\)"[^"]\{1,\}"/\1"********"   # مخفی شده/' "$conf"
```

- [ ] **Step 7: در dispatch و help ثبتش کن**

در `case`:

```sh
  apply-config|apply_config) cmd_apply_config "$@" ;;
```

در `cmd_help` زیر `edit`:

```sh
  say '  apply-config <سمت>       کانفیگ از stdin (JSON یا کلید=مقدار)'
```

- [ ] **Step 8: تست را اجرا کن و ببین پاس می‌شود**

```bash
sh tests/cli/test-apply-config.sh
```

انتظار: `0 fail`. اگر «کامنت نمونه‌ها ماند» شکست خورد، `set_conf_ports` کامنت‌ها را نگه نمی‌دارد — `keep` را با `sed -n '/ports/,/\]/p' | grep '#'` دستی روی `configs/server.toml` بسنج.

- [ ] **Step 9: مستندش کن**

در `docs/CLI.md` بعد از بخش `edit` یک بخش تازه:

```markdown
### `apply-config` — نوشتن کانفیگ از stdin

```bash
echo '{"transport":"wssmux","web_port":2060}' | sudo farshub apply-config server

printf 'log_level=debug\nports+=443\nports+=8443=443\n' |
  sudo farshub apply-config server
```

دو شکل ورودی: JSON (که `python3` می‌خواهد) یا خطوط `کلید=مقدار` که هیچ
وابستگی‌ای ندارد. `ports+=` تکرارشدنی است؛ `ports=` خالی، فهرست را پاک می‌کند.

خروجی به‌ازای هر کلید یک خط: `changed <کلید>` یا `unchanged <کلید>`.

**چرا این زیردستور وجود دارد.** موتور اجرا حالت اعتبارسنجی ندارد — فقط
`-config` می‌گیرد و با آن تونل را واقعاً بالا می‌آورد. پس اعتبارسنجی کار CLI
است: فهرست بسته‌ی کلیدها، یک نوع و یک بازه برای هر کلید، و قالب
`bind_addr` / `remote_addr` / ردیف‌های `ports`. نتیجه‌اش این است که کانفیگ
نامعتبر **پیش از** نوشتن رد می‌شود، نه بعد از ری‌استارت.

نوشتن اتمیک است: فایل موقت، بعد `mv` در همان filesystem. نسخه‌ی قبلی در
`<سمت>.toml.bak` می‌ماند، پس برگشت یک `mv` است.

و بدون این زیردستور، sudoers پنل وب باید `tee /etc/farshub/*` را اجازه بدهد —
یعنی نوشتن محتوای دلخواه در مسیر دلخواه.
```

- [ ] **Step 10: commit**

```bash
git add bin/farshub tests/cli/test-apply-config.sh docs/CLI.md
git commit -m "cli: apply-config — اعتبارسنجی allowlist و نوشتن اتمیک کانفیگ"
```

---

## Task 3: `bin/farshub-api` — هشت اندپوینت

سرویس API. هیچ TOML نمی‌نویسد و هیچ `systemctl` نمی‌زند؛ فقط `sudo farshub <زیردستور>` با آرگومان ثابت. تفکیک `handle()` از پوسته‌ی HTTP یعنی تست بدون سوکت و بدون وابستگی به پلتفرم.

**Files:**
- Create: `bin/farshub-api`, `systemd/farshub-api.service`, `tests/api/test_api.py`
- Modify: `bin/farshub` (`cmd_paths` — دو خط `installed_*`)

**Interfaces:**
- Consumes: از تسک ۱ → `farshub paths <side>` (بدون root، خطوط `key=value`)؛ از تسک ۲ → `farshub apply-config <side>` (JSON از stdin، خروجی `changed`/`unchanged`)؛ از پیش موجود → `farshub config|logs|install|start|stop|restart|enable|disable|token|panel-up`
- Produces:
  - `bin/farshub-api` سطح ماژول: `run_cli(args, stdin=None, root=True, timeout=25) → (rc, out, err)`، `handle(method, path, query, headers, body) → (int, dict)`، `Handler`، `main(argv) → int`، ثابت‌های `CLI`, `SUDO`, `WRITE_GAP`, `SIDES`, `ACTIONS`
  - `systemd/farshub-api.service` — `ExecStart=/usr/local/bin/farshub-api --port 2061`
  - `farshub paths` دو خط تازه: `installed_server=0|1`, `installed_client=0|1`

- [ ] **Step 1: تست شکست‌خورده را بنویس**

`tests/api/test_api.py`:

```python
"""تست‌های farshub-api.

هیچ سوکتی باز نمی‌شود و هیچ زیرفرایندی اجرا نمی‌شود: run_cli در سطح ماژول
جایگزین می‌شود. این تست‌ها روی ویندوز هم بی‌تغییر اجرا می‌شوند، پس توسعه
لازم نیست روی سرور انجام شود.
"""

import importlib.util
import json
import os
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def load():
    # فایل پسوند .py ندارد (یک اجرایی است)، پس با مسیر بارش می‌کنیم.
    path = os.path.join(REPO, "bin", "farshub-api")
    spec = importlib.util.spec_from_loader(
        "farshub_api", importlib.machinery.SourceFileLoader("farshub_api", path)
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


api = load()

ORIGIN = {"Origin": "http://box:8088", "Host": "box:8088"}

PATHS_OUT = (
    "side=server\n"
    "conf=/etc/farshub/server.toml\n"
    "unit=farshub-server.service\n"
    "site_name=farshub-panel\n"
    "installed_server=1\n"
    "installed_client=0\n"
)

CONFIG_OUT = (
    'bind_addr = "0.0.0.0:3080"\n'
    'transport = "tcpmux"\n'
    'token = "********"   # مخفی شده\n'
    "ports = [\n"
    '    "443",\n'
    "]\n"
    "web_port = 2060\n"
    'log_level = "warn"\n'
    "sniffer = false\n"
)


class Fake:
    """run_cli جعلی که فراخوانی‌ها را ضبط می‌کند."""

    def __init__(self, replies=None):
        self.calls = []
        self.replies = replies or {}

    def __call__(self, args, stdin=None, root=True, timeout=None):
        self.calls.append({"args": list(args), "stdin": stdin, "root": root})
        key = args[0]
        return self.replies.get(key, (0, "", ""))

    def args_of(self, name):
        return [c["args"] for c in self.calls if c["args"][0] == name]


class Base(unittest.TestCase):
    def setUp(self):
        self.fake = Fake(
            {
                "paths": (0, PATHS_OUT, ""),
                "config": (0, CONFIG_OUT, ""),
                "logs": (0, "line one\nline two\n", ""),
                "token": (0, "a" * 64 + "\n", ""),
            }
        )
        self._real = api.run_cli
        api.run_cli = self.fake
        api._last_write = 0.0

    def tearDown(self):
        api.run_cli = self._real

    def call(self, method, path, query=None, headers=None, body=None):
        h = dict(ORIGIN)
        if headers is not None:
            h = headers
        return api.handle(method, path, query or {}, h, body)


class TestRouting(Base):
    def test_unknown_path_is_404(self):
        st, out = self.call("GET", "/api/nope")
        self.assertEqual(st, 404)
        self.assertEqual(out["error"], "not_found")

    def test_wrong_method_is_405(self):
        st, out = self.call("DELETE", "/api/config")
        self.assertEqual(st, 405)

    def test_state_reports_install_and_service(self):
        st, out = self.call("GET", "/api/state")
        self.assertEqual(st, 200)
        self.assertTrue(out["installed"]["server"])
        self.assertFalse(out["installed"]["client"])
        self.assertIn("service", out)
        self.assertIn("unit", out["service"])

    def test_state_needs_no_root(self):
        self.call("GET", "/api/state")
        for c in self.fake.calls:
            if c["args"][0] == "paths":
                self.assertFalse(c["root"], "paths نباید با sudo صدا زده شود")


class TestOrigin(Base):
    def test_write_without_origin_is_rejected(self):
        st, out = self.call("PUT", "/api/config", headers={"Host": "box:8088"},
                            body={"side": "server", "values": {"log_level": "info"}})
        self.assertEqual(st, 403)
        self.assertEqual(out["error"], "origin")

    def test_write_with_foreign_origin_is_rejected(self):
        st, out = self.call(
            "PUT", "/api/config",
            headers={"Origin": "http://evil.example", "Host": "box:8088"},
            body={"side": "server", "values": {"log_level": "info"}},
        )
        self.assertEqual(st, 403)
        self.assertEqual(out["error"], "origin")

    def test_origin_must_match_port_too(self):
        st, out = self.call(
            "PUT", "/api/config",
            headers={"Origin": "http://box:9999", "Host": "box:8088"},
            body={"side": "server", "values": {"log_level": "info"}},
        )
        self.assertEqual(st, 403)

    def test_read_needs_no_origin(self):
        st, out = self.call("GET", "/api/state", headers={"Host": "box:8088"})
        self.assertEqual(st, 200)


class TestConfig(Base):
    def test_get_config_goes_through_cli(self):
        st, out = self.call("GET", "/api/config", query={"side": ["server"]})
        self.assertEqual(st, 200)
        self.assertEqual(out["side"], "server")
        self.assertEqual(out["values"]["transport"], "tcpmux")
        self.assertEqual(out["values"]["web_port"], 2060)
        self.assertIs(out["values"]["sniffer"], False)
        self.assertEqual(out["values"]["ports"], ["443"])
        self.assertEqual([["config", "server"]], self.fake.args_of("config"))

    def test_token_never_leaves_the_box(self):
        st, out = self.call("GET", "/api/config", query={"side": ["server"]})
        self.assertEqual(out["values"]["token"], "********")
        self.assertTrue(out["tokenSet"])

    def test_placeholder_token_is_reported_unset(self):
        self.fake.replies["config"] = (0, 'token = "CHANGE_ME"\n', "")
        st, out = self.call("GET", "/api/config", query={"side": ["server"]})
        self.assertFalse(out["tokenSet"])

    def test_put_sends_json_on_stdin(self):
        st, out = self.call("PUT", "/api/config",
                            body={"side": "server", "values": {"log_level": "info"}})
        self.assertEqual(st, 200)
        call = [c for c in self.fake.calls if c["args"][0] == "apply-config"][0]
        self.assertEqual(call["args"], ["apply-config", "server"])
        self.assertEqual(json.loads(call["stdin"]), {"log_level": "info"})
        self.assertTrue(call["root"])

    def test_put_reports_restart_needed(self):
        self.fake.replies["apply-config"] = (0, "changed log_level\n", "")
        st, out = self.call("PUT", "/api/config",
                            body={"side": "server", "values": {"log_level": "info"}})
        self.assertTrue(out["restartNeeded"])
        self.assertEqual(out["changed"], ["log_level"])

    def test_put_with_no_change_needs_no_restart(self):
        self.fake.replies["apply-config"] = (0, "unchanged log_level\n", "")
        st, out = self.call("PUT", "/api/config",
                            body={"side": "server", "values": {"log_level": "warn"}})
        self.assertFalse(out["restartNeeded"])

    def test_empty_token_field_is_dropped(self):
        st, out = self.call("PUT", "/api/config",
                            body={"side": "server", "values": {"token": "", "log_level": "info"}})
        call = [c for c in self.fake.calls if c["args"][0] == "apply-config"][0]
        self.assertNotIn("token", json.loads(call["stdin"]))

    def test_cli_failure_passes_persian_message_through(self):
        self.fake.replies["apply-config"] = (1, "", "transport نامعتبر: «quic»\n")
        st, out = self.call("PUT", "/api/config",
                            body={"side": "server", "values": {"transport": "quic"}})
        self.assertEqual(st, 400)
        self.assertEqual(out["error"], "cli_failed")
        self.assertIn("quic", out["detail"])

    def test_bad_side_is_rejected_before_the_cli(self):
        st, out = self.call("PUT", "/api/config",
                            body={"side": "../../etc", "values": {"log_level": "info"}})
        self.assertEqual(st, 400)
        self.assertEqual(out["error"], "bad_request")
        self.assertEqual(self.fake.calls, [])

    def test_values_must_be_an_object(self):
        st, out = self.call("PUT", "/api/config", body={"side": "server", "values": [1, 2]})
        self.assertEqual(st, 400)


class TestService(Base):
    def test_action_is_passed_as_fixed_argv(self):
        st, out = self.call("POST", "/api/service", body={"side": "server", "action": "restart"})
        self.assertEqual(st, 200)
        self.assertEqual([["restart", "server"]], self.fake.args_of("restart"))

    def test_unknown_action_is_rejected(self):
        st, out = self.call("POST", "/api/service", body={"side": "server", "action": "rm -rf /"})
        self.assertEqual(st, 400)
        self.assertEqual(self.fake.calls, [])

    def test_rate_limited(self):
        self.call("POST", "/api/service", body={"side": "server", "action": "restart"})
        st, out = self.call("POST", "/api/service", body={"side": "server", "action": "restart"})
        self.assertEqual(st, 429)
        self.assertEqual(out["error"], "rate_limit")

    def test_reads_are_not_rate_limited(self):
        self.call("POST", "/api/service", body={"side": "server", "action": "restart"})
        st, _ = self.call("GET", "/api/state")
        self.assertEqual(st, 200)


class TestInstall(Base):
    def test_install_then_config_then_panel_up(self):
        st, out = self.call(
            "POST", "/api/install",
            body={"side": "server", "values": {"bind_addr": "0.0.0.0:3080", "token": "b" * 40}},
        )
        self.assertEqual(st, 200)
        order = [c["args"][0] for c in self.fake.calls if c["args"][0] in
                 ("install", "apply-config", "panel-up")]
        self.assertEqual(order, ["install", "apply-config", "panel-up"])

    def test_install_stops_if_install_fails(self):
        self.fake.replies["install"] = (1, "", "دسترسی نوشتن نیست\n")
        st, out = self.call("POST", "/api/install", body={"side": "server", "values": {}})
        self.assertEqual(st, 400)
        self.assertEqual(self.fake.args_of("apply-config"), [])


class TestLogs(Base):
    def test_line_count_is_clamped(self):
        self.call("GET", "/api/logs", query={"side": ["server"], "n": ["100000"]})
        self.assertEqual([["logs", "server", "-n", "1000"]], self.fake.args_of("logs"))

    def test_non_numeric_n_falls_back(self):
        self.call("GET", "/api/logs", query={"side": ["server"], "n": ["-f"]})
        self.assertEqual([["logs", "server", "-n", "100"]], self.fake.args_of("logs"))


class TestToken(Base):
    def test_token_is_generated_without_root(self):
        st, out = self.call("POST", "/api/token")
        self.assertEqual(st, 200)
        self.assertEqual(len(out["token"]), 64)
        call = [c for c in self.fake.calls if c["args"][0] == "token"][0]
        self.assertFalse(call["root"], "token به root نیاز ندارد")


class TestPreflight(Base):
    def test_default_token_is_flagged(self):
        self.fake.replies["config"] = (
            0, 'bind_addr = "0.0.0.0:3080"\ntoken = "CHANGE_ME"\nports = [\n]\n', "")
        st, out = self.call("GET", "/api/preflight", query={"side": ["server"]})
        self.assertEqual(st, 200)
        ids = [c["id"] for c in out["checks"]]
        self.assertIn("pf.tokenDefault", ids)
        self.assertIn("pf.noPorts", ids)
        bad = [c for c in out["checks"] if c["id"] == "pf.tokenDefault"][0]
        self.assertEqual(bad["level"], "error")

    def test_wss_without_cert_is_flagged(self):
        self.fake.replies["config"] = (
            0, 'transport = "wssmux"\ntoken = "' + "c" * 40 + '"\ntls_cert = ""\n', "")
        st, out = self.call("GET", "/api/preflight", query={"side": ["server"]})
        self.assertIn("pf.tlsMissing", [c["id"] for c in out["checks"]])

    def test_clean_config_has_no_errors(self):
        self.fake.replies["config"] = (
            0,
            'bind_addr = "0.0.0.0:3080"\ntransport = "tcpmux"\ntoken = "' + "d" * 40 + '"\n'
            'ports = [\n    "443",\n]\nweb_port = 2060\nsniffer = false\n',
            "",
        )
        st, out = self.call("GET", "/api/preflight", query={"side": ["server"]})
        self.assertEqual([c for c in out["checks"] if c["level"] == "error"], [])

    def test_client_placeholder_remote_is_flagged(self):
        self.fake.replies["config"] = (
            0, 'remote_addr = "SERVER_IP:3080"\ntoken = "' + "e" * 40 + '"\n', "")
        st, out = self.call("GET", "/api/preflight", query={"side": ["client"]})
        self.assertIn("pf.remoteUnset", [c["id"] for c in out["checks"]])


class TestTimeout(Base):
    def test_timeout_becomes_504(self):
        self.fake.replies["restart"] = (-1, "", "timeout")
        st, out = self.call("POST", "/api/service", body={"side": "server", "action": "restart"})
        self.assertEqual(st, 504)
        self.assertEqual(out["error"], "timeout")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: تست را اجرا کن و ببین شکست می‌خورد**

```bash
sh tests/run.sh api
```

انتظار: خطای بار شدن ماژول — `bin/farshub-api` وجود ندارد.

- [ ] **Step 3: `installed_*` را به `cmd_paths` اضافه کن**

در `cmd_paths` (تسک ۱) بعد از خط `printf 'log=%s\n'`:

```sh
  # پنل باید بتواند «هنوز نصب نشده» را بدون root تشخیص بدهد — ویزارد سرور
  # خام روی همین سیگنال سوار است.
  [ -f "$CONF_DIR/server.toml" ] && printf 'installed_server=1\n' || printf 'installed_server=0\n'
  [ -f "$CONF_DIR/client.toml" ] && printf 'installed_client=1\n' || printf 'installed_client=0\n'
```

- [ ] **Step 4: `bin/farshub-api` — لایه‌ی فراخوانی CLI و کمکی‌ها**

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""farshub-api — پل باریک میان پنل وب و CLI فارس‌هاب.

این سرویس نه TOML می‌نویسد و نه systemctl می‌زند. هر کاری که root می‌خواهد از
«sudo farshub <زیردستور>» با آرگومان ثابت می‌گذرد، و sudoers هم همان فهرست
ثابت را اجازه می‌دهد. نتیجه: پنل و CLI نمی‌توانند از هم واگرا شوند، و بدترین
پیامد یک باگ اینجا «یک کانفیگ خراب و یک ری‌استارت» است، نه اجرای دلخواه.

روی 127.0.0.1 گوش می‌دهد. احراز هویت کار nginx است (auth_basic)، چون این
سرویس هیچ‌وقت مستقیم در دسترس شبکه نیست.
"""

import json
import os
import re
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, urlsplit

CLI = os.environ.get("FARSHUB_CLI", "/usr/local/bin/farshub")
SUDO = os.environ.get("FARSHUB_SUDO", "/usr/bin/sudo")

TIMEOUT = 25            # ثانیه — install روی شبکه‌ی کند هم باید جا شود
WRITE_GAP = 3.0         # حداقل فاصله‌ی دو عملیات نوشتاری
MAX_BODY = 64 * 1024
LOG_MIN, LOG_MAX, LOG_DEFAULT = 1, 1000, 100

SIDES = ("server", "client")
ACTIONS = ("start", "stop", "restart", "enable", "disable")

_last_write = 0.0
_write_lock = threading.Lock()


def run_cli(args, stdin=None, root=True, timeout=TIMEOUT):
    """CLI را با آرایه صدا می‌زند. shell=False، بدون استثنا.

    هیچ آرگومانی از رشته ساخته نمی‌شود، پس تزریق دستور ساختاراً ممکن نیست.
    برمی‌گرداند (rc, stdout, stderr)؛ rc == -1 یعنی مهلت تمام شد.
    """
    cmd = ([SUDO, "-n", CLI] if root else [CLI]) + [str(a) for a in args]
    try:
        p = subprocess.run(cmd, input=stdin, capture_output=True,
                           text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return -1, "", "مهلت اجرای دستور تمام شد."
    except OSError as e:
        return 127, "", "اجرای %s ممکن نشد: %s" % (cmd[0], e)
    return p.returncode, p.stdout, p.stderr


def systemctl_read(verb, unit):
    """فقط is-active و is-enabled. هیچ فعل نوشتاری از این تابع نمی‌گذرد."""
    if verb not in ("is-active", "is-enabled"):
        return "unknown"
    try:
        p = subprocess.run(["systemctl", verb, unit], capture_output=True,
                           text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"
    return (p.stdout or p.stderr).strip() or "unknown"


def err(status, code, detail=""):
    out = {"error": code}
    if detail:
        out["detail"] = detail.strip()
    return status, out


def cli_err(rc, out, errtext):
    """خطای CLI را به پاسخ HTTP تبدیل می‌کند و پیام فارسی را دست‌نخورده می‌برد."""
    if rc == -1:
        return err(504, "timeout", errtext)
    detail = (errtext or out or "").strip()
    return err(400, "cli_failed", detail)


def want_side(value):
    return value if value in SIDES else None


def parse_paths(text):
    out = {}
    for line in text.splitlines():
        if "=" in line:
            k, _, v = line.partition("=")
            out[k.strip()] = v.strip()
    return out


_NUM = re.compile(r"^-?[0-9]+$")


def parse_toml_lite(text):
    """کانفیگ چاپ‌شده‌ی «farshub config» را به dict تبدیل می‌کند.

    یک خواننده‌ی TOML کامل نیست و لازم هم نیست: شکل فایل را خودمان
    می‌نویسیم — کلیدهای سطح بالا، بولین/عدد/رشته، و یک آرایه‌ی ports.
    """
    values = {}
    rows = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            if rows is None:
                continue
        if rows is not None:
            if "]" in line:
                rows = [r for r in rows if r]
                values["ports"] = rows
                rows = None
                continue
            m = re.search(r'"([^"]*)"', line)
            if m:
                rows.append(m.group(1))
            continue
        if "=" not in line:
            continue
        k, _, v = line.partition("=")
        k = k.strip()
        v = v.strip()
        if not re.match(r"^[a-z_]+$", k):
            continue
        if v.startswith("["):
            if "]" in v:
                values[k] = re.findall(r'"([^"]*)"', v)
            else:
                rows = []
            continue
        v = re.sub(r"\s+#.*$", "", v).strip()
        if v.startswith('"'):
            values[k] = v.strip('"')
        elif v in ("true", "false"):
            values[k] = (v == "true")
        elif _NUM.match(v):
            values[k] = int(v)
        else:
            values[k] = v
    return values


def read_config(side):
    """کانفیگ از CLI می‌آید، نه از فایل: فایل root و 600 است.

    برمی‌گرداند (values, None) یا (None, پاسخ خطا).
    """
    rc, out, e = run_cli(["config", side])
    if rc != 0:
        if "کانفیگی" in (e or "") or "کانفیگ نیست" in (e or ""):
            return None, err(409, "not_installed", e)
        return None, cli_err(rc, out, e)
    return parse_toml_lite(out), None
```

- [ ] **Step 5: `bin/farshub-api` — اندپوینت‌ها و `handle()`**

در ادامه‌ی همان فایل:

```python
# ------------------------------------------------------------- اندپوینت‌ها --

def ep_state(query):
    rc, out, e = run_cli(["paths", query.get("side", ["server"])[0]
                          if want_side(query.get("side", [""])[0]) else "server"],
                         root=False)
    if rc != 0:
        return cli_err(rc, out, e)
    p = parse_paths(out)
    installed = {
        "server": p.get("installed_server") == "1",
        "client": p.get("installed_client") == "1",
    }
    side = None
    if installed["server"] != installed["client"]:
        side = "server" if installed["server"] else "client"
    unit = p.get("unit", "")
    return 200, {
        "installed": installed,
        "side": side,
        "service": {
            "unit": unit,
            "active": systemctl_read("is-active", unit) if unit else "unknown",
            "enabled": systemctl_read("is-enabled", unit) if unit else "unknown",
        },
        "paths": {k: v for k, v in p.items() if k in
                  ("conf", "site", "site_name", "web", "panel_state", "api_state")},
    }


def ep_get_config(query):
    side = want_side(query.get("side", [""])[0])
    if not side:
        return err(400, "bad_request", "پارامتر side باید server یا client باشد.")
    values, bad = read_config(side)
    if bad:
        return bad
    token = values.get("token", "")
    values["token"] = "********"
    return 200, {
        "side": side,
        "values": values,
        "tokenSet": bool(token) and token not in ("CHANGE_ME", "********") or token == "********",
    }


def ep_put_config(body):
    if not isinstance(body, dict):
        return err(400, "bad_request", "بدنه باید JSON باشد.")
    side = want_side(body.get("side"))
    if not side:
        return err(400, "bad_request", "side باید server یا client باشد.")
    values = body.get("values")
    if not isinstance(values, dict) or not values:
        return err(400, "bad_request", "values باید شیئی ناتهی باشد.")
    # فیلد خالی توکن یعنی «دست نزن»، نه «خالی کن».
    values = {k: v for k, v in values.items() if not (k == "token" and v in ("", "********"))}
    if not values:
        return 200, {"changed": [], "unchanged": [], "restartNeeded": False}
    rc, out, e = run_cli(["apply-config", side], stdin=json.dumps(values))
    if rc != 0:
        return cli_err(rc, out, e)
    changed, unchanged = [], []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[0] == "changed":
            changed.append(parts[1])
        elif len(parts) == 2 and parts[0] == "unchanged":
            unchanged.append(parts[1])
    return 200, {"changed": changed, "unchanged": unchanged,
                 "restartNeeded": bool(changed)}


def ep_install(body):
    if not isinstance(body, dict):
        return err(400, "bad_request", "بدنه باید JSON باشد.")
    side = want_side(body.get("side"))
    if not side:
        return err(400, "bad_request", "side باید server یا client باشد.")
    values = body.get("values") or {}
    if not isinstance(values, dict):
        return err(400, "bad_request", "values باید شیء باشد.")

    rc, out, e = run_cli(["install", side], timeout=90)
    if rc != 0:
        return cli_err(rc, out, e)
    steps = ["install"]

    applied = {"changed": [], "unchanged": []}
    values = {k: v for k, v in values.items() if not (k == "token" and v in ("", "********"))}
    if values:
        rc, cout, e = run_cli(["apply-config", side], stdin=json.dumps(values))
        if rc != 0:
            return cli_err(rc, cout, e)
        steps.append("apply-config")
        for line in cout.splitlines():
            parts = line.split()
            if len(parts) == 2 and parts[0] in applied:
                applied[parts[0]].append(parts[1])

    # panel-up نصب سمت را «تمام» می‌کند: web_port موتور، قاعده‌ی فایروال،
    # سایت nginx و panel.json.
    rc, pout, e = run_cli(["panel-up", side], timeout=90)
    if rc != 0:
        return cli_err(rc, pout, e)
    steps.append("panel-up")
    return 200, {"steps": steps, "changed": applied["changed"],
                 "unchanged": applied["unchanged"], "restartNeeded": True}


def ep_service(body):
    if not isinstance(body, dict):
        return err(400, "bad_request", "بدنه باید JSON باشد.")
    side = want_side(body.get("side"))
    action = body.get("action")
    if not side:
        return err(400, "bad_request", "side باید server یا client باشد.")
    if action not in ACTIONS:
        return err(400, "bad_request",
                   "action باید یکی از %s باشد." % ", ".join(ACTIONS))
    rc, out, e = run_cli([action, side], timeout=45)
    if rc != 0:
        return cli_err(rc, out, e)
    return 200, {"action": action, "side": side, "output": out.strip()}


def ep_token():
    rc, out, e = run_cli(["token"], root=False)
    if rc != 0:
        return cli_err(rc, out, e)
    token = out.strip().split()[-1] if out.strip() else ""
    if not re.match(r"^[A-Za-z0-9._~-]{32,256}$", token):
        return err(500, "cli_failed", "توکن تولیدشده معتبر نبود.")
    return 200, {"token": token}


def ep_logs(query):
    side = want_side(query.get("side", [""])[0])
    if not side:
        return err(400, "bad_request", "side باید server یا client باشد.")
    raw = query.get("n", [""])[0]
    try:
        n = int(raw)
    except (TypeError, ValueError):
        n = LOG_DEFAULT
    n = max(LOG_MIN, min(LOG_MAX, n))
    rc, out, e = run_cli(["logs", side, "-n", str(n)], timeout=15)
    if rc != 0:
        return cli_err(rc, out, e)
    return 200, {"side": side, "lines": out.splitlines()}


def ep_preflight(query):
    """چیزهایی که کانفیگ معتبر است ولی تونل با آن بالا نمی‌آید یا ناامن است."""
    side = want_side(query.get("side", [""])[0])
    if not side:
        return err(400, "bad_request", "side باید server یا client باشد.")
    v, bad = read_config(side)
    if bad:
        return bad
    checks = []

    def add(cid, level):
        checks.append({"id": cid, "level": level})

    token = v.get("token", "")
    if not token or token == "CHANGE_ME":
        add("pf.tokenDefault", "error")
    transport = v.get("transport", "")
    if transport in ("wss", "wssmux"):
        if not v.get("tls_cert") or not v.get("tls_key"):
            add("pf.tlsMissing", "error")
    if side == "server":
        if not v.get("ports"):
            add("pf.noPorts", "warn")
        addr = v.get("bind_addr", "")
        if addr:
            port = addr.rsplit(":", 1)[-1]
            if port.isdigit() and port_busy(int(port), side):
                add("pf.portBusy", "warn")
    else:
        remote = v.get("remote_addr", "")
        if not remote or remote.startswith("SERVER_IP:") or remote.startswith(":"):
            add("pf.remoteUnset", "error")
    if not v.get("web_port"):
        add("pf.webPortOff", "warn")
    if not v.get("sniffer"):
        add("pf.snifferOff", "info")
    return 200, {"side": side, "checks": checks}


def port_busy(port, side):
    """فقط یک اشاره است، نه حکم: اگر خود سرویس بالا باشد پورت طبعاً گرفته
    است. پس وقتی سرویس active است چیزی گزارش نمی‌کنیم."""
    rc, out, _ = run_cli(["paths", side], root=False)
    if rc == 0:
        unit = parse_paths(out).get("unit", "")
        if unit and systemctl_read("is-active", unit) == "active":
            return False
    try:
        import socket
        s = socket.socket()
        s.settimeout(0.3)
        try:
            s.bind(("", port))
            return False
        finally:
            s.close()
    except OSError:
        return True
    except Exception:
        return False


# ------------------------------------------------------------------ روتر --

READ_ROUTES = {
    "/api/state": lambda q, b: ep_state(q),
    "/api/config": lambda q, b: ep_get_config(q),
    "/api/logs": lambda q, b: ep_logs(q),
    "/api/preflight": lambda q, b: ep_preflight(q),
}

WRITE_ROUTES = {
    ("PUT", "/api/config"): lambda q, b: ep_put_config(b),
    ("POST", "/api/install"): lambda q, b: ep_install(b),
    ("POST", "/api/service"): lambda q, b: ep_service(b),
    ("POST", "/api/token"): lambda q, b: ep_token(),
}

ALL_PATHS = set(READ_ROUTES) | {p for _, p in WRITE_ROUTES}


def origin_ok(headers):
    """احراز هویت با HTTP Basic کوکی ندارد، پس SameSite هیچ کمکی نمی‌کند.
    چیزی که کمک می‌کند برابری Origin با Host است — و نبودن Origin هم رد.

    nginx باید «proxy_set_header Host $http_host;» بدهد؛ $host پورت را
    می‌اندازد و این مقایسه را همیشه شکست می‌دهد.
    """
    origin = headers.get("Origin") or headers.get("origin")
    host = headers.get("Host") or headers.get("host")
    if not origin or not host:
        return False
    try:
        parts = urlsplit(origin)
    except ValueError:
        return False
    return bool(parts.netloc) and parts.netloc == host


def handle(method, path, query, headers, body):
    """کل منطق سرویس. بدون سوکت، پس تست‌شدنی و مستقل از پلتفرم."""
    global _last_write

    path = path.rstrip("/") or "/"
    if path not in ALL_PATHS:
        return err(404, "not_found", "مسیر ناشناس: %s" % path)

    if method in ("GET", "HEAD"):
        fn = READ_ROUTES.get(path)
        if not fn:
            return err(405, "bad_request", "متد %s برای %s نیست." % (method, path))
        return fn(query, body)

    fn = WRITE_ROUTES.get((method, path))
    if not fn:
        return err(405, "bad_request", "متد %s برای %s نیست." % (method, path))

    if not origin_ok(headers):
        return err(403, "origin", "Origin نامعتبر یا نبود.")

    with _write_lock:
        now = time.monotonic()
        if now - _last_write < WRITE_GAP:
            return err(429, "rate_limit", "خیلی سریع — چند ثانیه صبر کنید.")
        _last_write = now
    return fn(query, body)
```

- [ ] **Step 6: `bin/farshub-api` — پوسته‌ی HTTP و `main`**

انتهای همان فایل:

```python
# ------------------------------------------------------------ پوسته‌ی HTTP --

class Handler(BaseHTTPRequestHandler):
    server_version = "farshub-api"
    sys_version = ""
    protocol_version = "HTTP/1.1"

    def _run(self, method):
        u = urlparse(self.path)
        body = None
        length = self.headers.get("Content-Length")
        if length:
            try:
                n = int(length)
            except ValueError:
                return self._send(*err(400, "bad_request", "Content-Length نامعتبر."))
            if n > MAX_BODY:
                return self._send(*err(413, "bad_request", "بدنه بزرگ است."))
            raw = self.rfile.read(n) if n > 0 else b""
            if raw:
                try:
                    body = json.loads(raw.decode("utf-8"))
                except (ValueError, UnicodeDecodeError) as e:
                    return self._send(*err(400, "bad_request", "JSON نامعتبر: %s" % e))
        try:
            status, payload = handle(method, u.path, parse_qs(u.query),
                                     dict(self.headers), body)
        except Exception as e:                       # هیچ درخواستی نباید سرویس را بخواباند
            sys.stderr.write("خطای غیرمنتظره: %r\n" % (e,))
            status, payload = err(500, "cli_failed", "خطای داخلی سرویس.")
        self._send(status, payload)

    def _send(self, status, payload):
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def do_GET(self):
        self._run("GET")

    def do_HEAD(self):
        self._run("HEAD")

    def do_POST(self):
        self._run("POST")

    def do_PUT(self):
        self._run("PUT")

    def log_message(self, fmt, *args):
        # journald خودش زمان می‌زند
        sys.stderr.write("%s\n" % (fmt % args))


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    host, port = "127.0.0.1", 2061
    while argv:
        a = argv.pop(0)
        if a in ("--port", "-p") and argv:
            port = int(argv.pop(0))
        elif a.startswith("--port="):
            port = int(a.split("=", 1)[1])
        elif a == "--host" and argv:
            host = argv.pop(0)
        elif a.startswith("--host="):
            host = a.split("=", 1)[1]
        elif a in ("-h", "--help"):
            sys.stdout.write(__doc__ + "\nگزینه‌ها: --host 127.0.0.1 --port 2061\n")
            return 0
        else:
            sys.stderr.write("گزینه‌ی ناشناس: %s\n" % a)
            return 2
    srv = ThreadingHTTPServer((host, port), Handler)
    srv.daemon_threads = True
    sys.stderr.write("farshub-api روی %s:%s\n" % (host, port))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 7: یونیت سرویس را بنویس**

`systemd/farshub-api.service`:

```ini
# سرویس API پنل وب فارس‌هاب.
#
# روی 127.0.0.1 گوش می‌دهد و هیچ‌وقت مستقیم در دسترس شبکه نیست — nginx جلویش
# است و auth_basic آنجاست.
#
# با کاربر بی‌shell «farshub-api» اجرا می‌شود و برای هر کار نیازمند root
# «sudo farshub <زیردستور>» را با آرگومان ثابت صدا می‌زند (فهرست ثابت در
# /etc/sudoers.d/farshub-api).
#
# دو تنظیم سخت‌سازی عمداً اینجا نیست:
#   NoNewPrivileges  → اجرای setuid را می‌بندد و sudo setuid است.
#   ProtectSystem    → mount namespace به بچه‌های root هم ارث می‌رسد، پس
#                      «sudo farshub apply-config» نمی‌تواند /etc/farshub را
#                      بنویسد. در برابر خودِ کاربر farshub-api هم چیزی اضافه
#                      نمی‌کند: مجوزهای معمولی یونیکس همان کار را می‌کنند.

[Unit]
Description=FarsHub Tunnel — سرویس API پنل
Documentation=https://github.com/saeedgh837/FarsHub-Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=farshub-api
Group=farshub-api
ExecStart=/usr/local/bin/farshub-api --host 127.0.0.1 --port 2061
Restart=always
RestartSec=3
SyslogIdentifier=farshub-api
StartLimitIntervalSec=300
StartLimitBurst=10

RuntimeDirectory=farshub-api
RuntimeDirectoryMode=0700
PrivateTmp=yes
PrivateDevices=yes
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictNamespaces=yes
LockPersonality=yes
MemoryMax=128M
TasksMax=64

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 8: تست را اجرا کن و ببین پاس می‌شود**

```bash
sh tests/run.sh api
```

انتظار: `OK` برای همه‌ی تست‌ها. اگر `test_state_needs_no_root` شکست خورد یعنی `ep_state` با `root=True` صدا می‌زند؛ `paths` root نمی‌خواهد و نباید در sudoers هم باشد.

- [ ] **Step 9: commit**

```bash
git add bin/farshub-api systemd/farshub-api.service tests/api bin/farshub
git commit -m "api: سرویس هشت‌اندپوینتی که فقط از راه sudo farshub کار می‌کند"
```

---

## Task 4: `api-up` / `api-down` / `setup` و مسیر `/api/` در nginx

سرویس API باید با یک دستور بالا بیاید و با یک دستور کامل برود — همان الگوی `panel-up`/`panel-down`. و `setup` سه دستور را یکی می‌کند تا سرور خام یک‌خطی راه بیفتد.

**Files:**
- Create: `configs/api.sudoers`, `tests/cli/test-write-site.sh`
- Modify: `bin/farshub` (`write_site` خط ۷۲۰، `cmd_panel_up`، `cmd_panel_down`، dispatch، `cmd_help`)
- Modify: `docs/CLI.md`

**Interfaces:**
- Consumes: از تسک ۱ → `resolve_site_paths`, `guess_side_soft`, `API_STATE`, `SITE_NAME`, `find_payload`؛ از تسک ۳ → `bin/farshub-api`, `systemd/farshub-api.service`
- Produces:
  - `write_site PANEL_PORT WEB_PORT [API_PORT]` — با آرگومان سوم بلوک `location /api/` هم می‌دهد
  - `farshub api-up [side] [--port N] [--user NAME]` — کاربر، sudoers، یونیت، سایت
  - `farshub api-down` — کامل برگشت‌پذیر
  - `farshub setup [side] [--password PW] [--port N] [--api-port N]` — `install` + `panel-up` + `api-up`
  - `$API_STATE` با کلیدهای `api_port=`, `api_user=`
  - ثابت‌های مشتق از `$UNIT_PREFIX`: `API_UNIT="$UNIT_PREFIX-api.service"`, `API_BIN="$BIN_DIR/$UNIT_PREFIX-api"`, `API_SUDOERS="/etc/sudoers.d/$UNIT_PREFIX-api"`, `DEFAULT_API_USER="$UNIT_PREFIX-api"`
  - حالت `. farshub --lib` که فایل را source می‌کند بدون اجرای dispatch

- [ ] **Step 1: تست شکست‌خورده‌ی `write_site` را بنویس**

`tests/cli/test-write-site.sh`:

```sh
#!/bin/sh
# write_site تنها جایی است که مرز شبکه‌ی پنل تعیین می‌شود، پس شکل خروجی‌اش
# تست دارد: چه چیزی پروکسی می‌شود و چه چیزی نه.
set -u
. "$(dirname -- "$0")/../lib.sh"

# تابع را از خود اسکریپت برمی‌داریم تا نسخه‌ی واقعی تست شود، نه یک کپی.
site_out() {
  env FARSHUB_SITE_NAME=farshub-test FARSHUB_STATE_DIR=/tmp/fh-test-state \
    sh -c '. "$1" --lib; write_site "$2" "$3" "${4:-}"' \
    _ "$FARSHUB" "$@" 2>/dev/null
}

# بدون پورت API
out=$(site_out 8099 2062)
assert_contains 'listen پنل' "$out" 'listen 8099;'
assert_contains 'auth_basic هست' "$out" 'auth_basic'
assert_contains 'satisfy any' "$out" 'satisfy any;'
assert_contains 'لوکال‌هاست بی‌رمز' "$out" 'allow 127.0.0.1;'
assert_contains 'بقیه ممنوع' "$out" 'deny  all;'
assert_contains 'stats پروکسی می‌شود' "$out" 'proxy_pass http://127.0.0.1:2062/stats;'
assert_contains 'لاگ دسترسی خاموش' "$out" 'access_log off;'
assert_missing 'pprof پروکسی نمی‌شود' "$out" 'pprof'
assert_missing 'بدون API، مسیر api نیست' "$out" 'location /api/'

# با پورت API
out=$(site_out 8099 2062 2063)
assert_contains 'مسیر api هست' "$out" 'location /api/'
assert_contains 'به پورت API می‌رود' "$out" 'proxy_pass http://127.0.0.1:2063/api/;'
# $host پورت را می‌اندازد و چک Origin را همیشه شکست می‌دهد
assert_contains 'Host با پورت پاس می‌شود' "$out" 'proxy_set_header Host              $http_host;'
assert_missing 'از $host تنها استفاده نمی‌شود' "$out" 'Host              $host;'
assert_contains 'مهلت خواندن بلند' "$out" 'proxy_read_timeout'

summary
```

- [ ] **Step 2: تست را اجرا کن و ببین شکست می‌خورد**

```bash
sh tests/cli/test-write-site.sh
```

انتظار: FAIL روی `مسیر api هست` — `write_site` آرگومان سوم ندارد. اگر همه‌ی assertionها FAIL شدند، پرچم `--lib` در `bin/farshub` نیست؛ Step 3 اضافه‌اش می‌کند.

- [ ] **Step 3: حالت `--lib` را به `bin/farshub` بده**

تنها راه تست کردن یک تابع sh بدون کپی‌کردنش این است که فایل source شود ولی dispatch اجرا نشود. بلافاصله بالای `case` انتهای فایل:

```sh
# «. farshub --lib» فایل را source می‌کند بدون اینکه دستوری اجرا شود — تنها
# راه تست کردن توابع داخلی بدون کپی گرفتن از آنها.
if [ "${1:-}" = '--lib' ]; then
  return 0 2>/dev/null || exit 0
fi
```

- [ ] **Step 4: `write_site` را با بلوک `/api/` بازنویسی کن**

خط ۷۲۰. آرگومان سوم اختیاری، و اگر داده شود بلوک API هم می‌آید:

```sh
write_site() {                          # $1=پورت پنل  $2=web_port  $3=پورت API (اختیاری)
  cat <<EOF
# ساخته‌ی «farshub panel-up» — با «farshub panel-down» حذف می‌شود.
# دست‌نویسی نکنید؛ اجرای بعدی panel-up بازنویسی‌اش می‌کند.
server {
    listen $1;
EOF
  have_ipv6 && printf '    listen [::]:%s;\n' "$1"
  cat <<EOF
    server_name _;

    root $STATE_DIR/web;
    index index.html;

    # موتور اجرا هیچ احراز هویتی ندارد، پس لایه‌ی رمز اینجاست.
    # از خود ماشین (تونل SSH) بدون رمز باز می‌شود.
    auth_basic           "$BRAND";
    auth_basic_user_file $HTPASSWD_FILE;
    satisfy any;
    allow 127.0.0.1;
    allow ::1;
    deny  all;

    # فقط همین دو مسیر پروکسی می‌شوند؛ بقیه‌ی موتور — از جمله /debug/pprof —
    # عمداً بیرون می‌ماند. پنل هر ۲ ثانیه poll می‌کند، پس لاگ دسترسی خاموش است
    # وگرنه روزی ۸۰ هزار خط روی دیسک می‌نشیند.
    location = /stats {
        access_log off;
        proxy_pass http://127.0.0.1:$2/stats;
    }
    location = /data {
        access_log off;
        proxy_pass http://127.0.0.1:$2/data;
    }
EOF
  if [ -n "${3:-}" ]; then
    cat <<EOF

    # سرویس API. زیر همان auth_basic بالا می‌ماند.
    #
    # \$http_host نه \$host: \$host پورت را می‌اندازد و سرویس Origin را با Host
    # مقایسه می‌کند، پس با \$host هر درخواست نوشتاری رد می‌شد.
    location /api/ {
        proxy_pass       http://127.0.0.1:$3/api/;
        proxy_http_version 1.1;
        proxy_set_header Host              \$http_host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        # install و restart می‌توانند چند ده ثانیه طول بکشند.
        proxy_read_timeout 120s;
        proxy_send_timeout 120s;
    }
EOF
  fi
  printf '}\n'
}
```

- [ ] **Step 5: `cmd_panel_up` را برای «هنوز سمتی نصب نیست» و پورت API آماده کن**

سه تغییر در `cmd_panel_up`:

الف) در مقدار‌دهی اولیه‌ی متغیرها `pport_given=0` و `aport=''` را اضافه کن، و در حلقه‌ی آرگومان‌ها هر جا `pport` تنظیم می‌شود `pport_given=1` هم بگذار. بعد بلوک `[ -n "$side" ] || side=$(guess_side panel-up)` را با این عوض کن:

```sh
  # سمت می‌تواند خالی بماند: روی سرور خام پنل باید بالا بیاید تا ویزارد دیده
  # شود، وگرنه راهی برای نصب از پنل نمی‌ماند.
  [ -n "$side" ] || side=$(guess_side_soft)

  # پورت پنل از حالت قبلی پیش‌فرض می‌گیرد، وگرنه اجرای دوباره‌ی panel-up پنلی
  # که روی پورت دلخواه است را به ۸۰۸۸ برمی‌گرداند.
  if [ "$pport_given" = 0 ] && [ -f "$PANEL_STATE" ]; then
    prev=$(sed -n 's/^panel_port=//p' "$PANEL_STATE" | head -n1)
    case $prev in ''|*[!0-9]*) : ;; *) pport=$prev ;; esac
  fi
```

ب) شرط‌های وابسته به کانفیگ مشروط شوند:

```sh
  if [ -n "$side" ]; then
    conf=$(side_conf "$side")
    [ -f "$conf" ] || die "کانفیگ نیست: $conf — اول «farshub install $side»."
  else
    conf=''
    say 'هنوز سمتی نصب نیست — پنل با ویزارد نصب بالا می‌آید.'
  fi
```

و هر جا `$conf` را می‌خواند یا می‌نویسد (کشف `web_port`، `set_conf_val`، drop-in فایروال، `panel_json`) با `if [ -n "$conf" ]; then ... fi` بپوش. توضیحش را همان‌جا بنویس:

```sh
  # بدون کانفیگ، web_port صفر می‌ماند، پس قاعده‌ی فایروال هم لازم نیست —
  # چیزی روی 2060 گوش نمی‌دهد. ویزارد بعد از install هر دو را می‌سازد.
```

بررسی `[ -d "$STATE_DIR/web" ]` هم مشروط شود: روی سرور خام `install` اجرا نشده، پس فایل‌های پنل باید از مخزن کپی شوند. اگر `$STATE_DIR/web` نبود، همان کار `cmd_install` را بکن:

```sh
  if [ ! -d "$STATE_DIR/web" ]; then
    src=$(find_payload)
    [ -d "$src/web" ] || die "فایل‌های پنل پیدا نشد در $src/web."
    install -d -m755 "$STATE_DIR/web"
    cp -R "$src/web/." "$STATE_DIR/web/"
    rm -f "$STATE_DIR/web/devserver.py"
    chmod -R u=rwX,go=rX "$STATE_DIR/web"
    say "  پنل    → $STATE_DIR/web"
  fi
```

ج) پورت API از `$API_STATE` خوانده شود تا `panel-up` بعدی مسیر `/api/` را نیندازد:

```sh
  # اگر سرویس API نصب است، مسیرش را از همین اول بنویس؛ وگرنه panel-up بعدی
  # مسیر /api/ را می‌انداخت و تب تنظیمات ۴۰۴ می‌گرفت.
  if [ -z "$aport" ] && [ -f "$API_STATE" ]; then
    aport=$(sed -n 's/^api_port=//p' "$API_STATE" | head -n1)
    case $aport in ''|*[!0-9]*) aport='' ;; esac
  fi
```

و فراخوانی را `write_site "$pport" "${wport:-0}" "$aport" >"$site"` کن.

- [ ] **Step 6: `cmd_panel_down` را با `resolve_site_paths` هم‌راست کن**

فهرست کاندیدهای هاردکد در `cmd_panel_down` جدا از `cmd_panel_up` بود و با `FARSHUB_SITE_NAME` هم‌قدم نمی‌شد. حلقه‌اش را با این عوض کن:

```sh
  resolve_site_paths
  for f in "$SITE_FILE" "/etc/nginx/sites-available/$SITE_NAME" \
           "/etc/nginx/conf.d/$SITE_NAME.conf"; do
```

و اگر سرویس API نصب است هشدار بده — `panel-down` سایت را می‌برد و API بی‌سایت می‌ماند:

```sh
  if [ -f "$API_STATE" ]; then
    say 'سرویس API هنوز نصب است ولی سایتش رفت — «farshub api-down» هم بزنید.'
  fi
```

- [ ] **Step 7: قالب sudoers را بنویس**

`configs/api.sudoers`:

```sudoers
# ساخته‌ی «farshub api-up» — با «farshub api-down» حذف می‌شود.
# دست‌نویسی نکنید. syntax اشتباه در sudoers می‌تواند sudo را برای همه بخواباند،
# پس api-up پیش از نصب با «visudo -c -f» می‌سنجدش.
#
# فهرست بسته است و هر ورودی آرگومان ثابت دارد. هیچ‌جا wildcard مسیر نیست، پس
# سرویس API نمی‌تواند فایل دلخواه بنویسد یا دستور دلخواه اجرا کند.
#
# «farshub paths» و «farshub token» اینجا نیستند: هیچ‌کدام root نمی‌خواهند و
# سرویس بی‌sudo صداشان می‌زند.
#
# در logs، «-n [0-9]*» عمدی است: با آن «-f» رد می‌شود، وگرنه لاگ زنده هرگز
# تمام نمی‌شد و سرویس روی همان درخواست گیر می‌کرد.
@@API_USER@@ ALL=(root) NOPASSWD: @@CLI@@ install server, \
  @@CLI@@ install client, \
  @@CLI@@ apply-config server, \
  @@CLI@@ apply-config client, \
  @@CLI@@ config server, \
  @@CLI@@ config client, \
  @@CLI@@ start server, @@CLI@@ start client, \
  @@CLI@@ stop server, @@CLI@@ stop client, \
  @@CLI@@ restart server, @@CLI@@ restart client, \
  @@CLI@@ enable server, @@CLI@@ enable client, \
  @@CLI@@ disable server, @@CLI@@ disable client, \
  @@CLI@@ panel-up server, @@CLI@@ panel-up client, \
  @@CLI@@ logs server -n [0-9]*, \
  @@CLI@@ logs client -n [0-9]*
```

- [ ] **Step 8: `cmd_api_up` را بنویس**

بعد از `cmd_panel_down`:

```sh
# ------------------------------------------------------------- سرویس API --
# هر سه نام از UNIT_PREFIX مشتق می‌شوند تا دو نمونه‌ی جدا روی یک سرور
# یونیت و sudoers همدیگر را بازنویسی نکنند (تصحیح ۴ در بالای این سند).
API_UNIT="$UNIT_PREFIX-api.service"
API_BIN="$BIN_DIR/$UNIT_PREFIX-api"
API_SUDOERS="/etc/sudoers.d/$UNIT_PREFIX-api"
DEFAULT_API_USER="$UNIT_PREFIX-api"

cmd_api_up() {
  side=''; aport=2061; auser="$DEFAULT_API_USER"
  while [ $# -gt 0 ]; do
    case $1 in
      --port)   [ $# -ge 2 ] || die '--port مقدار می‌خواهد.'; aport=$2; shift ;;
      --port=*) aport=${1#--port=} ;;
      --user)   [ $# -ge 2 ] || die '--user مقدار می‌خواهد.'; auser=$2; shift ;;
      --user=*) auser=${1#--user=} ;;
      server|s) side=server ;;
      client|c) side=client ;;
      *)        die "گزینه‌ی ناشناس: $1" ;;
    esac
    shift
  done
  case $aport in ''|*[!0-9]*) die "پورت API نامعتبر: «$aport»" ;; esac
  case $auser in ''|*[!a-z0-9_-]*) die "نام کاربری نامعتبر: «$auser»" ;; esac
  [ -n "$side" ] || side=$(guess_side_soft)

  need_root
  have_systemd || die 'api-up به systemd نیاز دارد.'
  [ -f "$PANEL_STATE" ] || die 'اول «farshub panel-up» — سرویس API زیر همان سایت nginx می‌نشیند.'

  src=$(find_payload)
  [ -f "$src/bin/farshub-api" ] || die "farshub-api پیدا نشد در $src/bin."

  say "راه‌اندازی سرویس API $BRAND"

  # ۱) کاربر بی‌shell. اگر باشد دست نمی‌خورد.
  if id "$auser" >/dev/null 2>&1; then
    say "  کاربر  → $auser (بود)"
  else
    useradd --system --no-create-home --shell /usr/sbin/nologin "$auser" 2>/dev/null ||
      adduser --system --no-create-home --shell /usr/sbin/nologin "$auser" ||
      die "ساخت کاربر $auser ممکن نشد."
    say "  کاربر  → $auser"
  fi

  # ۲) اجرایی
  install -Dm755 "$src/bin/farshub-api" "$API_BIN"
  say "  سرویس  → $API_BIN"

  # ۳) sudoers. اول در فایل موقت با visudo سنجیده می‌شود: یک syntax خراب در
  #    sudoers می‌تواند sudo را برای همه‌ی کاربران بخواباند.
  tmp=$(mktemp)
  sed -e "s|@@API_USER@@|$auser|g" -e "s|@@CLI@@|$BIN_DIR/farshub|g" \
      "$src/configs/api.sudoers" >"$tmp"
  chmod 440 "$tmp"
  if command -v visudo >/dev/null 2>&1; then
    visudo -c -q -f "$tmp" >/dev/null 2>&1 || {
      rm -f "$tmp"
      die 'قالب sudoers معتبر نبود — چیزی نصب نشد.'
    }
  fi
  install -Dm440 "$tmp" "$API_SUDOERS"
  rm -f "$tmp"
  say "  اجازه  → $API_SUDOERS"

  # ۴) یونیت. drop-in همیشه نوشته می‌شود: یونیت شیپ‌شده نام و پورت پیش‌فرض را
  #    دارد و ما نمی‌خواهیم روی فایل شیپ‌شده sed بزنیم.
  install -Dm644 "$src/systemd/farshub-api.service" "$UNIT_DIR/$API_UNIT"
  d="$UNIT_DIR/$API_UNIT.d"
  mkdir -p "$d"
  {
    printf '# ساخته‌ی «farshub api-up». دستی ویرایش نکنید.\n[Service]\n'
    printf 'User=%s\nGroup=%s\n' "$auser" "$auser"
    printf 'Environment=FARSHUB_CLI=%s/farshub\n' "$BIN_DIR"
    # متغیرهای انزوا هم به سرویس می‌رسند، وگرنه CLI که سرویس صدا می‌زند سراغ
    # نمونه‌ی پیش‌فرض می‌رفت. فقط آنهایی که واقعاً ست‌اند.
    for v in FARSHUB_CONF_DIR FARSHUB_LIBEXEC FARSHUB_STATE_DIR FARSHUB_LOG_DIR \
             FARSHUB_UNIT_DIR FARSHUB_UNIT_PREFIX FARSHUB_SITE_NAME FARSHUB_HTPASSWD \
             FARSHUB_BIN_DIR; do
      eval "val=\${$v:-}"
      [ -n "$val" ] && printf 'Environment=%s=%s\n' "$v" "$val"
    done
    printf 'ExecStart=\nExecStart=%s --host 127.0.0.1 --port %s\n' "$API_BIN" "$aport"
  } >"$d/10-farshub-env.conf"
  chmod 644 "$d/10-farshub-env.conf"
  say "  محیط   → $d/10-farshub-env.conf"

  systemctl daemon-reload
  systemctl enable --now "$API_UNIT" >/dev/null 2>&1 ||
    die "سرویس API بالا نیامد — «journalctl -u $API_UNIT -n 50» را ببینید."
  say "  یونیت  → $API_UNIT (فعال روی 127.0.0.1:$aport)"

  # ۵) حالت را بنویس، بعد سایت nginx را با مسیر /api/ دوباره بساز
  printf 'api_port=%s\napi_user=%s\n' "$aport" "$auser" >"$API_STATE"
  chmod 600 "$API_STATE"

  pport=$(sed -n 's/^panel_port=//p' "$PANEL_STATE" | head -n1)
  wport=$(sed -n 's/^web_port=//p'   "$PANEL_STATE" | head -n1)
  resolve_site_paths
  cp "$SITE_FILE" "$SITE_FILE.bak" 2>/dev/null || true
  write_site "${pport:-8088}" "${wport:-0}" "$aport" >"$SITE_FILE"
  if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1
    rm -f "$SITE_FILE.bak"
    say '  nginx  → مسیر /api/ اضافه شد'
  else
    [ -f "$SITE_FILE.bak" ] && mv "$SITE_FILE.bak" "$SITE_FILE"
    die 'nginx کانفیگ را نپذیرفت — به حالت قبل برگشت.'
  fi

  say ''
  say 'تنظیم تونل از همان پنل، تب «تنظیمات».'
  [ -n "$side" ] || say 'هنوز سمتی نصب نیست — پنل ویزارد نصب را نشان می‌دهد.'
}
```

- [ ] **Step 9: `cmd_api_down` را بنویس**

```sh
cmd_api_down() {
  need_root
  auser="$DEFAULT_API_USER"
  if [ -f "$API_STATE" ]; then
    prev=$(sed -n 's/^api_user=//p' "$API_STATE" | head -n1)
    [ -n "$prev" ] && auser=$prev
  fi

  say "برداشتن سرویس API $BRAND"

  if have_systemd; then
    systemctl disable --now "$API_UNIT" >/dev/null 2>&1 || true
    rm -f "$UNIT_DIR/$API_UNIT"
    rm -rf "$UNIT_DIR/$API_UNIT.d"
    systemctl daemon-reload
    say '  یونیت  → حذف شد'
  fi

  rm -f "$API_SUDOERS"
  say "  اجازه  → $API_SUDOERS حذف شد"
  rm -f "$API_BIN"
  rm -f "$API_STATE"

  # سایت nginx بدون مسیر /api/ دوباره نوشته می‌شود، وگرنه تب تنظیمات ۵۰۲ می‌داد.
  if [ -f "$PANEL_STATE" ]; then
    pport=$(sed -n 's/^panel_port=//p' "$PANEL_STATE" | head -n1)
    wport=$(sed -n 's/^web_port=//p'   "$PANEL_STATE" | head -n1)
    resolve_site_paths
    if [ -f "$SITE_FILE" ]; then
      write_site "${pport:-8088}" "${wport:-0}" >"$SITE_FILE"
      if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx >/dev/null 2>&1 || true
        say '  nginx  → مسیر /api/ برداشته شد'
      fi
    fi
  fi

  # کاربر می‌ماند: ممکن است چیز دیگری مالکش باشد و حذفش برگشت‌ناپذیر است.
  say ''
  say "کاربر «$auser» دست‌نخورده ماند. برای حذفش: userdel $auser"
  say 'پنل سر جایش است — فقط تب تنظیمات کار نمی‌کند.'
}
```

- [ ] **Step 10: `cmd_setup` را بنویس**

```sh
# سرور خام تا پنل باز، با یک دستور. هر سه گام idempotent‌اند، پس اجرای دوباره
# بی‌خطر است.
cmd_setup() {
  side=''; ppass=''; pport=''; aport=''
  while [ $# -gt 0 ]; do
    case $1 in
      --password)   [ $# -ge 2 ] || die '--password مقدار می‌خواهد.'; ppass=$2; shift ;;
      --password=*) ppass=${1#--password=} ;;
      --port)       [ $# -ge 2 ] || die '--port مقدار می‌خواهد.'; pport=$2; shift ;;
      --port=*)     pport=${1#--port=} ;;
      --api-port)   [ $# -ge 2 ] || die '--api-port مقدار می‌خواهد.'; aport=$2; shift ;;
      --api-port=*) aport=${1#--api-port=} ;;
      server|s)     side=server ;;
      client|c)     side=client ;;
      *)            die "گزینه‌ی ناشناس: $1" ;;
    esac
    shift
  done
  need_root
  have_systemd || die 'setup به systemd نیاز دارد.'

  say "راه‌اندازی کامل $BRAND"
  say ''

  # سمت اختیاری است: بدون آن پنل با ویزارد بالا می‌آید و کاربر از مرورگر
  # انتخاب می‌کند — همان چیزی که «سرور خام» را یک‌خطی می‌کند.
  if [ -n "$side" ]; then
    cmd_install "$side"
    say ''
  fi

  set --
  [ -n "$side" ]  && set -- "$@" "$side"
  [ -n "$pport" ] && set -- "$@" --port "$pport"
  [ -n "$ppass" ] && set -- "$@" --password "$ppass"
  cmd_panel_up "$@"
  say ''

  set --
  [ -n "$side" ]  && set -- "$@" "$side"
  [ -n "$aport" ] && set -- "$@" --port "$aport"
  cmd_api_up "$@"
}
```

- [ ] **Step 11: در dispatch و help ثبتشان کن**

```sh
  api-up|api_up)           cmd_api_up "$@" ;;
  api-down|api_down)       cmd_api_down "$@" ;;
  setup)                   cmd_setup "$@" ;;
```

در `cmd_help` زیر `panel-down`:

```sh
  say '  api-up [سمت]             سرویس API پنل (تب تنظیمات) را بالا بیاور'
  say '  api-down                 سرویس API را بردار'
  say '  setup [سمت]              نصب + پنل + API با یک دستور'
```

- [ ] **Step 12: تست‌ها را اجرا کن**

```bash
sh tests/run.sh cli
```

انتظار: هر سه فایل `0 fail`. تست‌های تسک ۱ و ۲ هم باید هنوز پاس باشند — `write_site` و `cmd_panel_up` دست خورده‌اند.

- [ ] **Step 13: مستندش کن**

در `docs/CLI.md` یک بخش تازه بعد از `panel-down`:

````markdown
### `api-up` / `api-down` — سرویس API پنل

```bash
sudo farshub api-up            # تب تنظیمات را فعال می‌کند
sudo farshub api-down          # فقط تب تنظیمات را می‌بندد؛ پنل سر جایش است
```

`api-up` پنج کار می‌کند: کاربر بی‌shell `farshub-api` را می‌سازد،
`farshub-api` را نصب می‌کند، فایل sudoers را با فهرست بسته‌ی زیردستورها
می‌گذارد (پیش از نصب با `visudo -c` سنجیده می‌شود)، یونیت را فعال می‌کند، و
سایت nginx را دوباره با `location /api/` می‌نویسد.

سرویس روی `127.0.0.1:2061` گوش می‌دهد و هیچ‌وقت مستقیم در دسترس شبکه نیست —
nginx جلویش است و همان `auth_basic` پنل رویش اعمال می‌شود.

**مرزی که این طرح می‌گذارد.** سرویس API هیچ TOML نمی‌نویسد و هیچ `systemctl`
نمی‌زند. هر کار نیازمند root از `sudo farshub <زیردستور>` با آرگومان ثابت
می‌گذرد و sudoers هم همان فهرست ثابت را اجازه می‌دهد. یعنی پنل و CLI
نمی‌توانند از هم واگرا شوند، و بدترین پیامد یک باگ در سرویس API «یک کانفیگ
خراب و یک ری‌استارت» است، نه اجرای دلخواه.

### `setup` — سرور خام تا پنل باز

```bash
sudo ./bin/farshub setup                          # سمت را از پنل انتخاب کنید
sudo ./bin/farshub setup server --password 'رمز'   # یا همین‌جا
```

`install` + `panel-up` + `api-up`. بدون سمت هم کار می‌کند: پنل بالا می‌آید و
ویزارد سه‌مرحله‌ای در مرورگر سمت را می‌پرسد و نصب می‌کند.
````

- [ ] **Step 14: commit**

```bash
git add bin/farshub configs/api.sudoers tests/cli/test-write-site.sh docs/CLI.md
git commit -m "cli: api-up/api-down/setup و مسیر /api/ در سایت nginx"
```

---

## Task 5: `config-schema.js` و `api.js` و mock‌های devserver

پایه‌ی سمت مرورگر: یک جدول کلیدها که فرم از آن ساخته می‌شود و همان‌جا اعتبارسنجی می‌کند، یک کلاینت API، و mock‌ها تا کل تب تنظیمات بدون سرور لینوکسی توسعه داده شود.

**Files:**
- Create: `web/assets/js/config-schema.js`, `web/assets/js/api.js`, `tests/web/config-schema.test.mjs`
- Modify: `web/devserver.py`

**Interfaces:**
- Consumes: از تسک ۳ → شکل پاسخ هشت اندپوینت و کدهای خطا (`origin`, `rate_limit`, `not_found`, `bad_request`, `not_installed`, `cli_failed`, `timeout`)
- Produces:
  - `config-schema.js` → `SCHEMA` (آرایه‌ی `{key, side, group, type, min, max, options, i18n, mono}`), `fieldsFor(side) → Field[]`, `groupsFor(side) → [{group, fields}]`, `validateField(field, raw) → {ok, value} | {ok:false, code, params}`, `validatePortRow(row) → {ok} | {ok:false, code, params}`, `validateAll(side, values) → {ok, values, errors}`, `TRANSPORTS`, `LOG_LEVELS`, `INSECURE_TRANSPORTS`
  - `api.js` → `ApiError` (با `code`, `detail`, `status`)، و `getState()`, `getConfig(side)`, `putConfig(side, values)`, `install(side, values)`, `service(side, action)`, `newToken()`, `getLogs(side, n)`, `preflight(side)`
  - `devserver.py` → mock هشت اندپوینت با حالت درون‌حافظه‌ای و پرچم‌های `?fresh=1`، `?apifail=1`

- [ ] **Step 1: تست شکست‌خورده را بنویس**

`tests/web/config-schema.test.mjs`:

```js
// اعتبارسنجی سمت مرورگر باید همان چیزهایی را رد کند که apply-config رد
// می‌کند — وگرنه کاربر فرم را پر می‌کند و خطای فارسی CLI را می‌گیرد بدون
// اینکه بداند کدام فیلد بود. سمت سرور هم دوباره می‌سنجد؛ این لایه فقط
// تجربه‌ی کاربری است، نه مرز امنیتی.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  SCHEMA, fieldsFor, groupsFor, validateField, validatePortRow, validateAll,
  TRANSPORTS, INSECURE_TRANSPORTS,
} from '../../web/assets/js/config-schema.js';

const field = (key) => SCHEMA.find((f) => f.key === key);

test('هر فیلد کلید i18n دارد', () => {
  for (const f of SCHEMA) {
    assert.ok(f.i18n, `${f.key} بدون کلید i18n`);
    assert.ok(f.group, `${f.key} بدون گروه`);
    assert.ok(f.type, `${f.key} بدون نوع`);
  }
});

test('فیلدهای هر سمت جدا می‌شوند', () => {
  const s = fieldsFor('server').map((f) => f.key);
  const c = fieldsFor('client').map((f) => f.key);
  assert.ok(s.includes('bind_addr'));
  assert.ok(s.includes('ports'));
  assert.ok(!s.includes('remote_addr'));
  assert.ok(c.includes('remote_addr'));
  assert.ok(c.includes('connection_pool'));
  assert.ok(!c.includes('ports'), 'کلاینت ports ندارد');
  assert.ok(s.includes('transport') && c.includes('transport'));
});

test('گروه‌ها به ترتیب می‌آیند و خالی نیستند', () => {
  const gs = groupsFor('server');
  assert.deepEqual(gs.map((g) => g.group), ['tunnel', 'ports', 'advanced']);
  for (const g of gs) assert.ok(g.fields.length > 0);
  assert.deepEqual(groupsFor('client').map((g) => g.group), ['tunnel', 'advanced']);
});

test('عدد بیرون بازه رد می‌شود', () => {
  const f = field('heartbeat');
  assert.equal(validateField(f, '40').ok, true);
  assert.equal(validateField(f, '40').value, 40);
  assert.equal(validateField(f, '0').ok, false);
  assert.equal(validateField(f, '0').code, 'err.range');
  assert.deepEqual(validateField(f, '0').params, { min: 1, max: 300 });
  assert.equal(validateField(f, '3.5').ok, false);
  assert.equal(validateField(f, 'x').ok, false);
  assert.equal(validateField(f, '').ok, false);
});

test('نشانی باید host:port باشد', () => {
  const f = field('bind_addr');
  assert.equal(validateField(f, '0.0.0.0:3080').ok, true);
  assert.equal(validateField(f, '[::]:3080').ok, true);
  assert.equal(validateField(f, '0.0.0.0').ok, false);
  assert.equal(validateField(f, '0.0.0.0:99999').ok, false);
  assert.equal(validateField(f, '0.0.0.0:0').ok, false);
  assert.equal(validateField(f, '0.0.0.0:3080"; rm -rf /').ok, false);
});

test('جای‌نگهدار remote_addr رد می‌شود', () => {
  const f = field('remote_addr');
  assert.equal(validateField(f, '1.2.3.4:3080').ok, true);
  assert.equal(validateField(f, 'SERVER_IP:3080').ok, false);
  assert.equal(validateField(f, 'SERVER_IP:3080').code, 'err.placeholder');
});

test('توکن کوتاه رد می‌شود، خالی یعنی دست نزن', () => {
  const f = field('token');
  assert.equal(validateField(f, '').ok, true, 'خالی مجاز است');
  assert.equal(validateField(f, '').value, undefined, 'خالی مقداری نمی‌فرستد');
  assert.equal(validateField(f, 'short').ok, false);
  assert.equal(validateField(f, 'short').code, 'err.tokenShort');
  assert.equal(validateField(f, 'a'.repeat(32)).ok, true);
  assert.equal(validateField(f, 'a'.repeat(31)).ok, false);
  assert.equal(validateField(f, 'a'.repeat(31) + ' ').ok, false);
  assert.equal(validateField(f, '@'.repeat(40)).ok, false);
});

test('transport فقط از فهرست', () => {
  const f = field('transport');
  for (const t of TRANSPORTS) assert.equal(validateField(f, t).ok, true, t);
  assert.equal(validateField(f, 'quic').ok, false);
  assert.deepEqual(f.options, TRANSPORTS);
  assert.ok(INSECURE_TRANSPORTS.includes('tcp'));
  assert.ok(!INSECURE_TRANSPORTS.includes('wss'));
});

test('بولین', () => {
  const f = field('nodelay');
  assert.deepEqual(validateField(f, true), { ok: true, value: true });
  assert.deepEqual(validateField(f, false), { ok: true, value: false });
});

test('مسیر باید مطلق باشد', () => {
  const f = field('sniffer_log');
  assert.equal(validateField(f, '').ok, true);
  assert.equal(validateField(f, '/var/log/x.json').ok, true);
  assert.equal(validateField(f, 'relative.json').ok, false);
  assert.equal(validateField(f, '/etc/x y').ok, false);
});

test('ردیف ports — همان قالب‌هایی که موتور می‌پذیرد', () => {
  for (const good of ['443', '443-600', '443-600:5201', '4000=5000',
                      '443=1.1.1.1:5201', '127.0.0.2:443=5201',
                      '127.0.0.2:443=1.1.1.1:5201', '443-600=1.1.1.1:5201']) {
    assert.equal(validatePortRow(good).ok, true, good);
  }
  for (const bad of ['', '0', '99999', '2100-2000', '443=', '=443', 'abc',
                     '999.1.1.1:443', '443 ; rm -rf /', '443-600-700']) {
    assert.equal(validatePortRow(bad).ok, false, bad);
  }
  assert.equal(validatePortRow('2100-2000').code, 'err.rangeOrder');
});

test('validateAll خطاها را با کلید فیلد برمی‌گرداند', () => {
  const r = validateAll('server', {
    bind_addr: '0.0.0.0:3080',
    heartbeat: '0',
    transport: 'tcpmux',
    token: '',
  });
  assert.equal(r.ok, false);
  assert.ok(r.errors.heartbeat);
  assert.equal(r.errors.heartbeat.code, 'err.range');
  assert.ok(!r.errors.bind_addr);
});

test('validateAll مقدارهای تایپ‌شده می‌دهد و توکن خالی را می‌اندازد', () => {
  const r = validateAll('server', {
    bind_addr: '0.0.0.0:3080',
    heartbeat: '40',
    nodelay: true,
    token: '',
    ports: ['443', '8443=443'],
  });
  assert.equal(r.ok, true);
  assert.equal(r.values.heartbeat, 40);
  assert.equal(r.values.nodelay, true);
  assert.ok(!('token' in r.values));
  assert.deepEqual(r.values.ports, ['443', '8443=443']);
});

test('validateAll کلید سمت مقابل را می‌اندازد', () => {
  const r = validateAll('server', { bind_addr: '0.0.0.0:3080', remote_addr: '1.2.3.4:80' });
  assert.equal(r.ok, true);
  assert.ok(!('remote_addr' in r.values));
});
```

- [ ] **Step 2: تست را اجرا کن و ببین شکست می‌خورد**

```bash
node --test tests/web/
```

انتظار: `ERR_MODULE_NOT_FOUND` — `config-schema.js` نیست.

- [ ] **Step 3: `web/assets/js/config-schema.js` را بنویس**

```js
// جدول کلیدهای کانفیگ — تنها منبع حقیقت فرم تنظیمات.
//
// فرم از همین آرایه ساخته می‌شود، پس افزودن یک کلید تازه یعنی یک ردیف تازه
// اینجا و دو کلید i18n، نه دست‌کاری HTML.
//
// اعتبارسنجی اینجا فقط برای تجربه‌ی کاربری است: مرز واقعی «farshub
// apply-config» است که همه چیز را دوباره و مستقل می‌سنجد. با این حال بازه‌ها
// و قالب‌ها عیناً همان‌هایی هستند که CLI می‌پذیرد، وگرنه کاربر خطای فارسی
// CLI را می‌گرفت بدون اینکه بداند کدام فیلد بوده.
//
// مقادیر از docs/UPSTREAM-BACKHAUL.md می‌آیند و در موتور کامپایل شده‌اند.

export const TRANSPORTS = ['tcp', 'tcpmux', 'ws', 'wsmux', 'wss', 'wssmux', 'udp'];
export const LOG_LEVELS = ['panic', 'fatal', 'error', 'warn', 'info', 'debug', 'trace'];

// اینها رمزنگاری ندارند. wss/wssmux دارند.
export const INSECURE_TRANSPORTS = ['tcp', 'tcpmux', 'ws', 'wsmux', 'udp'];

const BOTH = 'both';

export const SCHEMA = [
  // --- تونل ---------------------------------------------------------------
  { key: 'bind_addr',   side: 'server', group: 'tunnel', type: 'addr',  i18n: 'cfg.bindAddr',   mono: true },
  { key: 'remote_addr', side: 'client', group: 'tunnel', type: 'addr',  i18n: 'cfg.remoteAddr', mono: true, noPlaceholder: true },
  { key: 'transport',   side: BOTH,     group: 'tunnel', type: 'enum',  i18n: 'cfg.transport',  options: TRANSPORTS },
  { key: 'token',       side: BOTH,     group: 'tunnel', type: 'token', i18n: 'cfg.token',      mono: true, secret: true },
  { key: 'edge_ip',     side: 'client', group: 'tunnel', type: 'ip',    i18n: 'cfg.edgeIp',     mono: true, optional: true },

  // --- پورت‌ها (فقط سرور) --------------------------------------------------
  { key: 'ports',       side: 'server', group: 'ports',  type: 'ports', i18n: 'cfg.ports' },
  { key: 'accept_udp',  side: 'server', group: 'ports',  type: 'bool',  i18n: 'cfg.acceptUdp' },

  // --- پیشرفته ------------------------------------------------------------
  { key: 'heartbeat',         side: 'server', group: 'advanced', type: 'int', min: 1, max: 300, i18n: 'cfg.heartbeat' },
  { key: 'channel_size',      side: 'server', group: 'advanced', type: 'int', min: 64, max: 65536, i18n: 'cfg.channelSize' },
  { key: 'mux_con',           side: 'server', group: 'advanced', type: 'int', min: 1, max: 64, i18n: 'cfg.muxCon' },
  { key: 'connection_pool',   side: 'client', group: 'advanced', type: 'int', min: 1, max: 1024, i18n: 'cfg.connectionPool' },
  { key: 'aggressive_pool',   side: 'client', group: 'advanced', type: 'bool', i18n: 'cfg.aggressivePool' },
  { key: 'retry_interval',    side: 'client', group: 'advanced', type: 'int', min: 1, max: 300, i18n: 'cfg.retryInterval' },
  { key: 'dial_timeout',      side: 'client', group: 'advanced', type: 'int', min: 1, max: 300, i18n: 'cfg.dialTimeout' },
  { key: 'keepalive_period',  side: BOTH, group: 'advanced', type: 'int', min: 1, max: 3600, i18n: 'cfg.keepalive' },
  { key: 'nodelay',           side: BOTH, group: 'advanced', type: 'bool', i18n: 'cfg.nodelay' },
  { key: 'mux_version',       side: BOTH, group: 'advanced', type: 'int', min: 1, max: 2, i18n: 'cfg.muxVersion' },
  { key: 'mux_framesize',     side: BOTH, group: 'advanced', type: 'int', min: 4096, max: 1048576, i18n: 'cfg.muxFramesize' },
  { key: 'mux_recievebuffer', side: BOTH, group: 'advanced', type: 'int', min: 65536, max: 67108864, i18n: 'cfg.muxRecvBuffer' },
  { key: 'mux_streambuffer',  side: BOTH, group: 'advanced', type: 'int', min: 16384, max: 16777216, i18n: 'cfg.muxStreamBuffer' },
  { key: 'tls_cert',          side: BOTH, group: 'advanced', type: 'path', i18n: 'cfg.tlsCert', mono: true, optional: true },
  { key: 'tls_key',           side: BOTH, group: 'advanced', type: 'path', i18n: 'cfg.tlsKey',  mono: true, optional: true },
  { key: 'sniffer',           side: BOTH, group: 'advanced', type: 'bool', i18n: 'cfg.sniffer' },
  { key: 'sniffer_log',       side: BOTH, group: 'advanced', type: 'path', i18n: 'cfg.snifferLog', mono: true, optional: true },
  { key: 'web_port',          side: BOTH, group: 'advanced', type: 'int', min: 0, max: 65535, i18n: 'cfg.webPort' },
  { key: 'log_level',         side: BOTH, group: 'advanced', type: 'enum', options: LOG_LEVELS, i18n: 'cfg.logLevel' },
  { key: 'pprof',             side: BOTH, group: 'advanced', type: 'bool', i18n: 'cfg.pprof', danger: true },
];

const GROUP_ORDER = ['tunnel', 'ports', 'advanced'];

export function fieldsFor(side) {
  return SCHEMA.filter((f) => f.side === side || f.side === BOTH);
}

export function groupsFor(side) {
  const fields = fieldsFor(side);
  return GROUP_ORDER
    .map((group) => ({ group, fields: fields.filter((f) => f.group === group) }))
    .filter((g) => g.fields.length > 0);
}

const fail = (code, params) => ({ ok: false, code, params });

const PORT_OK = (n) => Number.isInteger(n) && n >= 1 && n <= 65535;

function ipOk(ip) {
  const parts = ip.split('.');
  return parts.length === 4 &&
    parts.every((p) => /^[0-9]{1,3}$/.test(p) && Number(p) <= 255);
}

// [bindip:]port[-port][= یا :][remoteip:]port
const ROW_RE = /^(?:(\d{1,3}(?:\.\d{1,3}){3}):)?(\d{1,5})(?:-(\d{1,5}))?(?:[=:](?:(\d{1,3}(?:\.\d{1,3}){3}):)?(\d{1,5}))?$/;

export function validatePortRow(row) {
  const s = String(row ?? '').trim();
  if (!s) return fail('err.required');
  const m = ROW_RE.exec(s);
  if (!m) return fail('err.portRow');
  const [, bindIp, lo, hi, remoteIp, dest] = m;
  for (const ip of [bindIp, remoteIp]) {
    if (ip && !ipOk(ip)) return fail('err.ip', { value: ip });
  }
  for (const p of [lo, hi, dest]) {
    if (p !== undefined && !PORT_OK(Number(p))) return fail('err.port', { value: p });
  }
  if (hi !== undefined && Number(lo) > Number(hi)) {
    return fail('err.rangeOrder', { min: lo, max: hi });
  }
  return { ok: true, value: s };
}

const ADDR_RE = /^(?:\[[0-9A-Fa-f:]{2,45}\]|[A-Za-z0-9_.-]{0,253}):(\d{1,5})$/;

export function validateField(field, raw) {
  switch (field.type) {
    case 'bool':
      return { ok: true, value: raw === true || raw === 'true' };

    case 'int': {
      const s = String(raw ?? '').trim();
      if (!/^\d+$/.test(s)) return fail('err.range', { min: field.min, max: field.max });
      const n = Number(s);
      if (n < field.min || n > field.max) {
        return fail('err.range', { min: field.min, max: field.max });
      }
      return { ok: true, value: n };
    }

    case 'enum': {
      const s = String(raw ?? '');
      return field.options.includes(s) ? { ok: true, value: s } : fail('err.choice');
    }

    case 'token': {
      const s = String(raw ?? '');
      // خالی یعنی «دست نزن» — توکن هیچ‌وقت از سرور خوانده نمی‌شود، پس فیلد
      // همیشه خالی شروع می‌شود و خالی ماندنش نباید خطا باشد.
      if (s === '') return { ok: true, value: undefined };
      if (!/^[A-Za-z0-9._~-]+$/.test(s)) return fail('err.tokenChars');
      if (s.length < 32 || s.length > 256) return fail('err.tokenShort', { min: 32 });
      return { ok: true, value: s };
    }

    case 'addr': {
      const s = String(raw ?? '').trim();
      if (!s) return fail('err.required');
      const m = ADDR_RE.exec(s);
      if (!m) return fail('err.addr');
      if (!PORT_OK(Number(m[1]))) return fail('err.port', { value: m[1] });
      if (field.noPlaceholder && /^(SERVER_IP|):/.test(s)) return fail('err.placeholder');
      return { ok: true, value: s };
    }

    case 'ip': {
      const s = String(raw ?? '').trim();
      if (!s) return field.optional ? { ok: true, value: undefined } : fail('err.required');
      return ipOk(s) ? { ok: true, value: s } : fail('err.ip', { value: s });
    }

    case 'path': {
      const s = String(raw ?? '').trim();
      if (!s) return { ok: true, value: '' };
      if (!/^\/[A-Za-z0-9._/-]{1,255}$/.test(s)) return fail('err.path');
      return { ok: true, value: s };
    }

    case 'ports': {
      const rows = Array.isArray(raw) ? raw : [];
      const cleaned = [];
      for (const r of rows) {
        const v = validatePortRow(r);
        if (!v.ok) return v;
        cleaned.push(v.value);
      }
      return { ok: true, value: cleaned };
    }

    default:
      return fail('err.unknown');
  }
}

export function validateAll(side, values) {
  const fields = fieldsFor(side);
  const out = {};
  const errors = {};
  for (const f of fields) {
    if (!(f.key in values)) continue;
    const r = validateField(f, values[f.key]);
    if (!r.ok) errors[f.key] = { code: r.code, params: r.params };
    else if (r.value !== undefined) out[f.key] = r.value;
  }
  return { ok: Object.keys(errors).length === 0, values: out, errors };
}
```

- [ ] **Step 4: تست را اجرا کن و ببین پاس می‌شود**

```bash
node --test tests/web/
```

انتظار: `pass 14`, `fail 0`.

- [ ] **Step 5: `web/assets/js/api.js` را بنویس**

```js
// کلاینت /api/*. همان الگوی getJSON در data.js — AbortController برای مهلت،
// خطا با پیام قابل نمایش.
//
// خطاها همیشه ApiError می‌شوند و کد ماشینی سرویس را حمل می‌کنند، پس صفحه
// می‌تواند «rate_limit» را نرم و «origin» را جدی بگیرد بدون تطبیق رشته.

const BASE = '/api';
const READ_TIMEOUT = 8000;
const WRITE_TIMEOUT = 130000;   // install و restart می‌توانند طول بکشند

export class ApiError extends Error {
  constructor(code, detail, status) {
    super(detail || code);
    this.name = 'ApiError';
    this.code = code;
    this.detail = detail || '';
    this.status = status || 0;
  }
}

async function call(method, path, { body, query, timeoutMs } = {}) {
  const url = new URL(BASE + path, window.location.origin);
  for (const [k, v] of Object.entries(query || {})) {
    if (v !== undefined && v !== null) url.searchParams.set(k, String(v));
  }
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeoutMs || READ_TIMEOUT);
  let res;
  try {
    res = await fetch(url, {
      method,
      signal: ctl.signal,
      headers: body
        ? { Accept: 'application/json', 'Content-Type': 'application/json' }
        : { Accept: 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch (e) {
    clearTimeout(timer);
    if (e.name === 'AbortError') throw new ApiError('timeout', '', 0);
    throw new ApiError('network', String(e.message || e), 0);
  } finally {
    clearTimeout(timer);
  }

  let payload = null;
  try {
    payload = await res.json();
  } catch {
    // یعنی nginx یا خود سرویس چیزی غیر JSON داد — 502 و مثل آن
  }
  if (!res.ok) {
    throw new ApiError(
      (payload && payload.error) || `http_${res.status}`,
      (payload && payload.detail) || '',
      res.status,
    );
  }
  return payload || {};
}

export const getState   = () => call('GET', '/state');
export const getConfig  = (side) => call('GET', '/config', { query: { side } });
export const preflight  = (side) => call('GET', '/preflight', { query: { side } });
export const getLogs    = (side, n = 100) => call('GET', '/logs', { query: { side, n } });

export const putConfig = (side, values) =>
  call('PUT', '/config', { body: { side, values }, timeoutMs: WRITE_TIMEOUT });

export const install = (side, values) =>
  call('POST', '/install', { body: { side, values }, timeoutMs: WRITE_TIMEOUT });

export const service = (side, action) =>
  call('POST', '/service', { body: { side, action }, timeoutMs: WRITE_TIMEOUT });

export const newToken = () => call('POST', '/token', { body: {} });
```

- [ ] **Step 6: mock‌ها را به `web/devserver.py` اضافه کن**

بالای کلاس `Handler`، بعد از `PANEL_META`:

```python
# --------------------------------------------------------------- mock API --
# حالت درون‌حافظه‌ای تا کل تب تنظیمات و ویزارد بدون سرور لینوکسی توسعه پیدا
# کند. شکل پاسخ‌ها عیناً همان است که bin/farshub-api می‌دهد.
#
#   ?fresh=1     → «هیچ سمتی نصب نیست» تا ویزارد دیده شود
#   ?apifail=1   → هر نوشتن با cli_failed رد می‌شود، تا مسیر خطا دیده شود

API_CONFIG = {
    "server": {
        "bind_addr": "0.0.0.0:3080",
        "transport": "tcpmux",
        "token": "********",
        "ports": ["443", "8443=443"],
        "accept_udp": False,
        "heartbeat": 40,
        "channel_size": 2048,
        "mux_con": 8,
        "keepalive_period": 75,
        "nodelay": True,
        "mux_version": 1,
        "mux_framesize": 32768,
        "mux_recievebuffer": 4194304,
        "mux_streambuffer": 65536,
        "tls_cert": "",
        "tls_key": "",
        "sniffer": False,
        "sniffer_log": "/var/log/farshub/sniffer.json",
        "web_port": 2060,
        "log_level": "warn",
        "pprof": False,
    },
    "client": {
        "remote_addr": "1.2.3.4:3080",
        "transport": "tcpmux",
        "token": "********",
        "edge_ip": "",
        "connection_pool": 8,
        "aggressive_pool": False,
        "retry_interval": 3,
        "dial_timeout": 10,
        "keepalive_period": 75,
        "nodelay": True,
        "mux_version": 1,
        "mux_framesize": 32768,
        "mux_recievebuffer": 4194304,
        "mux_streambuffer": 65536,
        "tls_cert": "",
        "tls_key": "",
        "sniffer": False,
        "sniffer_log": "/var/log/farshub/sniffer.json",
        "web_port": 2060,
        "log_level": "warn",
        "pprof": False,
    },
}

API_STATE = {"installed": {"server": True, "client": False}, "active": "active",
             "enabled": "enabled", "tokenSet": True}
```

در `do_GET`، پیش از dispatch موجود:

```python
        if path.startswith("/api/"):
            return self._api("GET")
```

و دو متد تازه روی `Handler`:

```python
    def do_POST(self):
        self._api("POST")

    def do_PUT(self):
        self._api("PUT")

    def _api(self, method):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        fresh = "fresh" in q or "fresh" in parse_qs(urlparse(self.headers.get(
            "Referer", "")).query)
        body = {}
        n = int(self.headers.get("Content-Length") or 0)
        if n:
            try:
                body = json.loads(self.rfile.read(n).decode("utf-8"))
            except ValueError:
                return self._json({"error": "bad_request", "detail": "JSON نامعتبر"}, 400)
        side = body.get("side") or (q.get("side", ["server"])[0])
        if side not in ("server", "client"):
            return self._json({"error": "bad_request", "detail": "side نامعتبر"}, 400)
        path = u.path.rstrip("/")

        if method in ("POST", "PUT") and "apifail" in q:
            return self._json(
                {"error": "cli_failed", "detail": "transport نامعتبر: «quic»"}, 400)

        if path == "/api/state" and method == "GET":
            installed = ({"server": False, "client": False} if fresh
                         else dict(API_STATE["installed"]))
            only = [k for k, v in installed.items() if v]
            return self._json({
                "installed": installed,
                "side": only[0] if len(only) == 1 else None,
                "service": {"unit": "farshub-%s.service" % side,
                            "active": "inactive" if fresh else API_STATE["active"],
                            "enabled": "disabled" if fresh else API_STATE["enabled"]},
                "paths": {"conf": "/etc/farshub/%s.toml" % side},
            })

        if path == "/api/config" and method == "GET":
            return self._json({"side": side, "values": dict(API_CONFIG[side]),
                               "tokenSet": API_STATE["tokenSet"]})

        if path == "/api/config" and method == "PUT":
            values = body.get("values") or {}
            changed = [k for k, v in values.items() if API_CONFIG[side].get(k) != v]
            unchanged = [k for k in values if k not in changed]
            API_CONFIG[side].update(
                {k: v for k, v in values.items() if k != "token"})
            if values.get("token"):
                API_STATE["tokenSet"] = True
                API_CONFIG[side]["token"] = "********"
            return self._json({"changed": changed, "unchanged": unchanged,
                               "restartNeeded": bool(changed)})

        if path == "/api/install" and method == "POST":
            API_STATE["installed"][side] = True
            API_CONFIG[side].update(
                {k: v for k, v in (body.get("values") or {}).items() if k != "token"})
            if (body.get("values") or {}).get("token"):
                API_STATE["tokenSet"] = True
            return self._json({"steps": ["install", "apply-config", "panel-up"],
                               "changed": list(body.get("values") or {}),
                               "unchanged": [], "restartNeeded": True})

        if path == "/api/service" and method == "POST":
            action = body.get("action")
            if action not in ("start", "stop", "restart", "enable", "disable"):
                return self._json({"error": "bad_request", "detail": "action نامعتبر"}, 400)
            if action in ("start", "restart"):
                API_STATE["active"] = "active"
            elif action == "stop":
                API_STATE["active"] = "inactive"
            elif action == "enable":
                API_STATE["enabled"] = "enabled"
            else:
                API_STATE["enabled"] = "disabled"
            return self._json({"action": action, "side": side, "output": "انجام شد."})

        if path == "/api/token" and method == "POST":
            import secrets
            return self._json({"token": secrets.token_hex(32)})

        if path == "/api/logs" and method == "GET":
            try:
                n = min(1000, max(1, int(q.get("n", ["100"])[0])))
            except ValueError:
                n = 100
            return self._json({"side": side, "lines": [
                "%s INFO  خط نمونه‌ی لاگ شماره %d" % ("2026-09-06T12:00:00Z", i)
                for i in range(1, min(n, 40) + 1)]})

        if path == "/api/preflight" and method == "GET":
            checks = []
            v = API_CONFIG[side]
            if not API_STATE["tokenSet"]:
                checks.append({"id": "pf.tokenDefault", "level": "error"})
            if v.get("transport") in ("wss", "wssmux") and not v.get("tls_cert"):
                checks.append({"id": "pf.tlsMissing", "level": "error"})
            if side == "server" and not v.get("ports"):
                checks.append({"id": "pf.noPorts", "level": "warn"})
            if not v.get("web_port"):
                checks.append({"id": "pf.webPortOff", "level": "warn"})
            if not v.get("sniffer"):
                checks.append({"id": "pf.snifferOff", "level": "info"})
            return self._json({"side": side, "checks": checks})

        return self._json({"error": "not_found", "detail": path}, 404)
```

`_json` باید کد وضعیت بگیرد. امضایش را به `_json(self, payload, status=200)` عوض کن و `self.send_response(status)` بگذار — تک فراخوانی موجودش بی‌تغییر کار می‌کند. `import json` و `from urllib.parse import urlparse, parse_qs` هم بالای فایل باید باشند، و `/api/` در فهرست خاموشی `log_message` اضافه شود.

- [ ] **Step 7: دستی بسنجش**

```bash
python web/devserver.py --port 8770
```

در ترمینال دیگر:

```bash
curl -s http://127.0.0.1:8770/api/state | python -m json.tool
```

انتظار: `installed.server = true`. بعد نوشتن:

```bash
curl -s -X PUT http://127.0.0.1:8770/api/config -H 'Content-Type: application/json' -d '{"side":"server","values":{"log_level":"info"}}'
```

انتظار: `{"changed": ["log_level"], "unchanged": [], "restartNeeded": true}`.

- [ ] **Step 8: commit**

```bash
git add web/assets/js/config-schema.js web/assets/js/api.js web/devserver.py tests/web
git commit -m "پنل: جدول کلیدهای کانفیگ، کلاینت API و mockهای devserver"
```

---

## Task 6: تب‌ها، کارت سرویس، CSS و i18n

اسکلت رابط. بعد از این تسک پنل دو تب دارد و کارت سرویس کار می‌کند؛ فرم کانفیگ در تسک ۷ می‌آید.

**Files:**
- Create: `web/assets/js/router.js`
- Modify: `web/index.html`, `web/assets/js/app.js`, `web/assets/js/i18n.js`, `web/assets/css/panel.css`

**Interfaces:**
- Consumes: از تسک ۵ → `api.js` (`getState`, `service`)؛ از پیش موجود → `i18n.js` (`t`, `applyDocumentLocale`, `LOCALES`), `app.js` (چرخه‌ی poll)
- Produces:
  - `router.js` → `route()` (خواندن hash فعلی)، `go(name)`, `onRoute(fn) → unsubscribe`, `ROUTES = ['dashboard', 'settings']`
  - `i18n.js` → `tf(key, params)` که `{min}`/`{max}`/`{value}` را جا می‌گذارد؛ و همه‌ی کلیدهای `tab.`, `svc.`, `cfg.`, `err.`, `pf.`, `wz.`, `save.`
  - `index.html` → `<nav class="tabs">` با دو دکمه، `<section id="view-dashboard">` (محتوای فعلی)، `<section id="view-settings">`، `<section id="view-wizard">`
  - `app.js` → `startPolling()` / `stopPolling()` و صدا زدنشان از روتر
  - CSS: `.tabs`, `.tab`, `.card`, `.field`, `.field__label`, `.field__hint`, `.field__err`, `.input`, `.select`, `.switch`, `.btn`, `.btn--primary`, `.btn--danger`, `.btn--ghost`, `.rows`, `.row`, `.bar`, `.bar--warn`, `.dlg`, `.steps`, `.step`, `.chip`, `.chip--error/warn/info`

- [ ] **Step 1: `tf()` را به `i18n.js` اضافه کن**

بعد از تابع `t`:

```js
// t با جای‌گذاری: tf('err.range', {min: 1, max: 300}).
// خیلی از پیام‌های خطا عدد دارند و بدون این، هر بازه یک کلید جدا می‌خواست.
export function tf(key, params) {
  let s = t(key);
  if (!params) return s;
  for (const [k, v] of Object.entries(params)) {
    s = s.split('{' + k + '}').join(num(v));
  }
  return s;
}
```

- [ ] **Step 2: کلیدهای تازه را در هر دو زبان بنویس**

در `STRINGS.fa`، بعد از گروه `unit.`:

```js
  // --- تب‌ها
  'tab.dashboard': 'داشبورد',
  'tab.settings': 'تنظیمات',

  // --- کارت سرویس
  'svc.title': 'سرویس',
  'svc.state': 'وضعیت',
  'svc.boot': 'اجرا در بوت',
  'svc.start': 'شروع',
  'svc.stop': 'توقف',
  'svc.restart': 'ری‌استارت',
  'svc.enable': 'فعال در بوت',
  'svc.disable': 'غیرفعال در بوت',
  'svc.confirmTitle': 'مطمئنید؟',
  'svc.confirmRestart': 'ری‌استارت سرویس همه‌ی اتصال‌های فعلی را قطع می‌کند. کاربران باید دوباره وصل شوند.',
  'svc.confirmStop': 'توقف سرویس تونل را می‌خواباند و همه‌ی اتصال‌ها قطع می‌شوند.',
  'svc.confirmDisable': 'با غیرفعال کردن، سرویس بعد از ری‌استارت سرور خودش بالا نمی‌آید.',
  'svc.confirmYes': 'بله، انجام بده',
  'svc.confirmNo': 'انصراف',
  'svc.done': 'انجام شد.',

  // --- ذخیره و ری‌استارت
  'save.save': 'ذخیره',
  'save.saving': 'در حال ذخیره…',
  'save.saved': 'ذخیره شد.',
  'save.needRestart': 'تغییرها ذخیره شد — برای اعمال، ری‌استارت لازم است.',
  'save.restartNow': 'ری‌استارت کن',
  'save.nothing': 'چیزی عوض نشده.',
  'save.hasErrors': 'چند فیلد اشکال دارد — پیام‌های زیر فیلدها را ببینید.',
  'save.reload': 'بازخوانی',
  'save.discard': 'برگرداندن تغییرها',

  // --- کلیدهای کانفیگ
  'cfg.tunnel': 'تونل',
  'cfg.ports': 'پورت‌ها',
  'cfg.advanced': 'پیشرفته',
  'cfg.bindAddr': 'نشانی گوش دادن',
  'cfg.bindAddr.hint': 'مثل 0.0.0.0:3080 — سرور روی این نشانی منتظر کلاینت می‌ماند.',
  'cfg.remoteAddr': 'نشانی سرور',
  'cfg.remoteAddr.hint': 'همان bind_addr سمت سرور. کلاینت همیشه خودش وصل می‌شود.',
  'cfg.transport': 'پروتکل',
  'cfg.transport.hint': 'دو سمت باید یکی باشند.',
  'cfg.transport.insecure': 'این پروتکل رمزنگاری ندارد. برای رمزنگاری wss یا wssmux با گواهی TLS.',
  'cfg.token': 'توکن',
  'cfg.token.hint': 'دو سمت باید عیناً یکی باشند. خالی بگذارید تا توکن فعلی دست نخورد.',
  'cfg.token.generate': 'تولید',
  'cfg.token.copy': 'رونوشت',
  'cfg.token.copied': 'رونوشت شد',
  'cfg.token.unset': 'توکن هنوز تنظیم نشده.',
  'cfg.edgeIp': 'IP لبه',
  'cfg.edgeIp.hint': 'فقط برای ws/wss — اتصال به این IP می‌رود ولی نام میزبان همان می‌ماند.',
  'cfg.ports.hint': 'هر ردیف یکی از این قالب‌ها: 443 یا 8443=443 یا 2000-2100',
  'cfg.ports.add': 'افزودن ردیف',
  'cfg.ports.remove': 'حذف',
  'cfg.ports.empty': 'هیچ پورتی تنظیم نشده — تونل بالا می‌آید ولی ترافیکی جابه‌جا نمی‌کند.',
  'cfg.acceptUdp': 'پذیرش UDP روی TCP',
  'cfg.heartbeat': 'ضربان (ثانیه)',
  'cfg.channelSize': 'اندازه‌ی صف',
  'cfg.muxCon': 'اتصال‌های mux',
  'cfg.connectionPool': 'استخر اتصال',
  'cfg.aggressivePool': 'استخر تهاجمی',
  'cfg.retryInterval': 'فاصله‌ی تلاش دوباره (ثانیه)',
  'cfg.dialTimeout': 'مهلت اتصال (ثانیه)',
  'cfg.keepalive': 'زنده‌نگهداری (ثانیه)',
  'cfg.nodelay': 'بی‌تأخیر (Nagle خاموش)',
  'cfg.muxVersion': 'نسخه‌ی mux',
  'cfg.muxFramesize': 'اندازه‌ی فریم mux',
  'cfg.muxRecvBuffer': 'بافر دریافت mux',
  'cfg.muxStreamBuffer': 'بافر جریان mux',
  'cfg.tlsCert': 'گواهی TLS',
  'cfg.tlsKey': 'کلید TLS',
  'cfg.sniffer': 'ثبت ترافیک',
  'cfg.snifferLog': 'فایل ثبت ترافیک',
  'cfg.webPort': 'پورت آمار موتور',
  'cfg.webPort.hint': 'صفر یعنی خاموش. پنل برای نمودارها به آن نیاز دارد.',
  'cfg.logLevel': 'سطح لاگ',
  'cfg.pprof': 'pprof',
  'cfg.pprof.hint': 'ابزار اشکال‌زدایی. روی سرور واقعی خاموش بماند.',

  // --- خطاهای فیلد
  'err.required': 'این فیلد لازم است.',
  'err.range': 'باید عددی بین {min} و {max} باشد.',
  'err.choice': 'از فهرست انتخاب کنید.',
  'err.addr': 'قالب درست: میزبان:پورت',
  'err.port': 'پورت نامعتبر: {value}',
  'err.ip': 'IP نامعتبر: {value}',
  'err.path': 'مسیر مطلق بدون فاصله لازم است.',
  'err.portRow': 'قالب ردیف درست نیست.',
  'err.rangeOrder': 'ابتدای بازه ({min}) از انتهایش ({max}) بزرگ‌تر است.',
  'err.tokenShort': 'دست‌کم {min} نویسه.',
  'err.tokenChars': 'فقط حرف، رقم و . _ ~ -',
  'err.placeholder': 'نشانی واقعی سرور را بگذارید.',
  'err.unknown': 'مقدار نامعتبر.',

  // --- خطاهای سرویس API
  'api.origin': 'درخواست از مبدأ ناشناس رد شد. صفحه را دوباره باز کنید.',
  'api.rate_limit': 'خیلی سریع — چند ثانیه صبر کنید.',
  'api.not_installed': 'هنوز نصب نشده.',
  'api.cli_failed': 'دستور اجرا نشد.',
  'api.timeout': 'پاسخی نرسید. ممکن است کار انجام شده باشد — صفحه را بازخوانی کنید.',
  'api.network': 'ارتباط با سرور قطع است.',
  'api.unavailable': 'سرویس تنظیمات نصب نیست. روی سرور: sudo farshub api-up',

  // --- preflight
  'pf.title': 'پیش از راه‌اندازی',
  'pf.ok': 'همه چیز مرتب است.',
  'pf.tokenDefault': 'توکن هنوز تنظیم نشده — تونل با توکن پیش‌فرض بالا نمی‌آید.',
  'pf.tlsMissing': 'پروتکل wss انتخاب شده ولی گواهی یا کلید TLS تنظیم نیست.',
  'pf.portBusy': 'پورت گوش دادن روی این سرور گرفته است.',
  'pf.noPorts': 'هیچ پورتی تنظیم نشده — تونل ترافیکی جابه‌جا نمی‌کند.',
  'pf.webPortOff': 'پورت آمار موتور خاموش است — نمودارهای داشبورد خالی می‌مانند.',
  'pf.snifferOff': 'ثبت ترافیک خاموش است. جدول پورت‌ها فقط با آن پر می‌شود.',
  'pf.remoteUnset': 'نشانی سرور تنظیم نشده.',

  // --- ویزارد
  'wz.title': 'راه‌اندازی',
  'wz.intro': 'روی این سرور هنوز چیزی نصب نیست. سه گام تا تونل زنده.',
  'wz.step1': 'نقش این سرور',
  'wz.step2': 'تنظیم‌های پایه',
  'wz.step3': 'بازبینی و نصب',
  'wz.server': 'سرور',
  'wz.serverDesc': 'روی سرور ایران می‌نشیند و منتظر کلاینت می‌ماند. کاربران به این وصل می‌شوند.',
  'wz.client': 'کلاینت',
  'wz.clientDesc': 'روی سرور خارج می‌نشیند و خودش به سرور وصل می‌شود.',
  'wz.next': 'بعدی',
  'wz.back': 'قبلی',
  'wz.installNow': 'نصب و راه‌اندازی',
  'wz.installing': 'در حال نصب…',
  'wz.done': 'نصب شد. سرویس را شروع کنید.',
  'wz.review': 'این مقادیر نوشته می‌شوند:',
  'wz.tokenNote': 'این توکن را نگه دارید — عیناً همین باید روی سمت دیگر تونل بنشیند.',
```

در `STRINGS.en` همان کلیدها با ترجمه‌ی انگلیسی. نمونه‌ی چند مورد که لحن را نگه می‌دارد:

```js
  'tab.dashboard': 'Dashboard',
  'tab.settings': 'Settings',
  'svc.title': 'Service',
  'svc.confirmRestart': 'Restarting drops every current connection. Users will have to reconnect.',
  'save.needRestart': 'Saved — a restart is needed to apply.',
  'cfg.bindAddr': 'Listen address',
  'cfg.bindAddr.hint': 'Like 0.0.0.0:3080 — the server waits for the client here.',
  'cfg.remoteAddr.hint': 'The server side bind_addr. The client always dials out.',
  'cfg.token.hint': 'Both sides must match exactly. Leave empty to keep the current token.',
  'cfg.transport.insecure': 'This transport is not encrypted. Use wss or wssmux with a TLS certificate for encryption.',
  'err.range': 'Must be a number between {min} and {max}.',
  'err.rangeOrder': 'Range start ({min}) is above its end ({max}).',
  'pf.tokenDefault': 'Token is still unset — the tunnel will not come up with the default.',
  'wz.serverDesc': 'Runs on the Iran box and waits for the client. Users connect here.',
  'api.unavailable': 'The settings service is not installed. On the server: sudo farshub api-up',
```

بقیه را به همین سبک کامل کن. **هر کلیدی که در `fa` هست باید در `en` هم باشد** — `t` روی کلید نبوده به انگلیسی و بعد به خود کلید سقوط می‌کند، پس کلید جامانده به‌صورت `cfg.muxCon` روی صفحه دیده می‌شود.

- [ ] **Step 3: `router.js` را بنویس**

```js
// روتر hash. دو مسیر، بدون کتابخانه.
//
// hash انتخاب شد نه History API: پنل از فایل سیستم سرو می‌شود و هیچ rewrite
// سمت سرور ندارد، پس /settings یک ۴۰۴ واقعی می‌داد.

export const ROUTES = ['dashboard', 'settings'];
const DEFAULT = 'dashboard';

export function route() {
  const raw = (window.location.hash || '').replace(/^#\/?/, '').split('?')[0];
  return ROUTES.includes(raw) ? raw : DEFAULT;
}

export function go(name) {
  const target = ROUTES.includes(name) ? name : DEFAULT;
  if (route() === target) return;
  window.location.hash = '#/' + target;
}

const listeners = new Set();

export function onRoute(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

window.addEventListener('hashchange', () => {
  const r = route();
  for (const fn of listeners) {
    try { fn(r); } catch (e) { console.error(e); }
  }
});
```

- [ ] **Step 4: اسکلت HTML را اضافه کن**

در `web/index.html`، بلافاصله بعد از هدر و پیش از محتوای فعلی:

```html
      <nav class="tabs" role="tablist" aria-label="بخش‌های پنل">
        <button class="tab is-active" role="tab" id="tab-dashboard"
                aria-controls="view-dashboard" aria-selected="true"
                data-route="dashboard" data-i18n="tab.dashboard">داشبورد</button>
        <button class="tab" role="tab" id="tab-settings"
                aria-controls="view-settings" aria-selected="false"
                data-route="settings" data-i18n="tab.settings">تنظیمات</button>
      </nav>
```

کل محتوای فعلی صفحه را در `<section id="view-dashboard" role="tabpanel" aria-labelledby="tab-dashboard">` بپیچ، و بعدش دو بخش خالی:

```html
      <section id="view-settings" role="tabpanel" aria-labelledby="tab-settings" hidden>
        <div class="bar bar--warn" id="restart-bar" hidden role="status">
          <span data-i18n="save.needRestart">تغییرها ذخیره شد — برای اعمال، ری‌استارت لازم است.</span>
          <button class="btn btn--primary" id="restart-now" data-i18n="save.restartNow">ری‌استارت کن</button>
        </div>

        <article class="card" id="card-service">
          <h2 class="card__title" data-i18n="svc.title">سرویس</h2>
          <dl class="card__facts">
            <dt data-i18n="svc.state">وضعیت</dt><dd id="svc-active">—</dd>
            <dt data-i18n="svc.boot">اجرا در بوت</dt><dd id="svc-enabled">—</dd>
          </dl>
          <div class="card__actions">
            <button class="btn btn--primary" data-action="start"   data-i18n="svc.start">شروع</button>
            <button class="btn btn--primary" data-action="restart" data-i18n="svc.restart">ری‌استارت</button>
            <button class="btn btn--danger"  data-action="stop"    data-i18n="svc.stop">توقف</button>
            <button class="btn btn--ghost"   data-action="enable"  data-i18n="svc.enable">فعال در بوت</button>
            <button class="btn btn--ghost"   data-action="disable" data-i18n="svc.disable">غیرفعال در بوت</button>
          </div>
        </article>

        <div id="settings-forms"></div>
      </section>

      <section id="view-wizard" hidden></section>

      <dialog class="dlg" id="confirm-dlg">
        <h2 class="dlg__title" data-i18n="svc.confirmTitle">مطمئنید؟</h2>
        <p class="dlg__body" id="confirm-body"></p>
        <div class="dlg__actions">
          <button class="btn btn--ghost"  id="confirm-no"  data-i18n="svc.confirmNo">انصراف</button>
          <button class="btn btn--danger" id="confirm-yes" data-i18n="svc.confirmYes">بله، انجام بده</button>
        </div>
      </dialog>
```

- [ ] **Step 5: تب‌ها و توقف poll را به `app.js` بده**

چرخه‌ی poll فعلی را در دو تابع بپیچ و از روتر صداشان بزن:

```js
// در تب تنظیمات poll متوقف می‌شود: /stats را هر ۲ ثانیه گرفتن وقتی کاربر
// دارد فرم پر می‌کند فقط CPU و لاگ می‌سوزاند، و بدتر، ذخیره را کند می‌کند.
let pollTimer = null;

function startPolling() {
  if (pollTimer) return;
  tick();
  pollTimer = setInterval(tick, POLL_MS);
}

function stopPolling() {
  if (!pollTimer) return;
  clearInterval(pollTimer);
  pollTimer = null;
}
```

و سوار کردن روتر:

این تسک `settings.js` و `wizard.js` را **import نمی‌کند** — آن دو فایل هنوز
وجود ندارند و یک import شکست‌خورده کل ماژول را از کار می‌انداخت. جایشان دو
قلاب خالی می‌گذاریم که تسک‌های ۷ و ۸ پرشان می‌کنند:

```js
import { route, go, onRoute } from './router.js';
import { getState } from './api.js';

// تسک ۷ این را با mountSettings از settings.js عوض می‌کند.
let mountSettings = () => {};
// تسک ۸ این را با mountWizard از wizard.js عوض می‌کند.
let mountWizard = () => {};

const views = {
  dashboard: document.getElementById('view-dashboard'),
  settings: document.getElementById('view-settings'),
};

function showRoute(name) {
  for (const [key, el] of Object.entries(views)) {
    el.hidden = key !== name;
  }
  for (const btn of document.querySelectorAll('.tab')) {
    const on = btn.dataset.route === name;
    btn.classList.toggle('is-active', on);
    btn.setAttribute('aria-selected', on ? 'true' : 'false');
  }
  if (name === 'settings') { stopPolling(); mountSettings(); }
  else { startPolling(); }
}

for (const btn of document.querySelectorAll('.tab')) {
  btn.addEventListener('click', () => go(btn.dataset.route));
}
onRoute(showRoute);

// اگر سرویس API نصب نباشد تب تنظیمات معنا ندارد؛ و اگر هیچ سمتی نصب نباشد
// جای هر دو تب، ویزارد می‌آید.
(async () => {
  try {
    const st = await getState();
    if (!st.installed.server && !st.installed.client) {
      document.querySelector('.tabs').hidden = true;
      views.dashboard.hidden = true;
      views.settings.hidden = true;
      mountWizard();
      return;
    }
  } catch (e) {
    // سرویس API نصب نیست — پنل ایستا مثل قبل کار می‌کند، فقط تب تنظیمات
    // غیرفعال می‌شود.
    const tab = document.getElementById('tab-settings');
    tab.disabled = true;
    tab.title = t('api.unavailable');
  }
  showRoute(route());
})();
```

- [ ] **Step 6: CSS را اضافه کن**

انتهای `web/assets/css/panel.css`، با توکن‌های موجود و بدون رنگ تازه:

```css
/* ============================================================ تنظیمات == */
/* همه‌ی رنگ‌ها از توکن‌های بالا می‌آیند تا تم روشن هم بی‌کار اضافه درست شود. */

.tabs {
  display: flex;
  gap: 2px;
  margin-block-end: var(--gap);
  border-block-end: 1px solid var(--line);
}

.tab {
  padding: 0.6rem 1.1rem;
  font: inherit;
  font-size: var(--step--1);
  color: var(--ink-muted);
  background: transparent;
  border: 0;
  border-block-end: 2px solid transparent;
  cursor: pointer;
  transition: color 0.15s var(--ease), border-color 0.15s var(--ease);
}
.tab:hover:not(:disabled) { color: var(--ink); }
.tab.is-active { color: var(--accent); border-block-end-color: var(--accent); }
.tab:disabled { opacity: 0.4; cursor: not-allowed; }
.tab:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }

[data-locale='en'] .tab { letter-spacing: 0.02em; }

.card {
  padding: var(--pad);
  margin-block-end: var(--gap);
  background: var(--bg-raised);
  border: 1px solid var(--line);
  border-radius: var(--r-lg);
  box-shadow: var(--shadow-tile);
}
.card__title {
  margin: 0 0 var(--gap);
  font-size: var(--step-1);
  font-weight: 600;
}
.card__facts {
  display: grid;
  grid-template-columns: max-content 1fr;
  gap: 0.35rem 1rem;
  margin: 0 0 var(--gap);
  font-size: var(--step--1);
}
.card__facts dt { color: var(--ink-muted); }
.card__facts dd { margin: 0; font-family: var(--font-mono); }
.card__actions { display: flex; flex-wrap: wrap; gap: 0.5rem; }

/* --- دکمه --------------------------------------------------------------- */
.btn {
  padding: 0.5rem 1rem;
  font: inherit;
  font-size: var(--step--1);
  color: var(--ink);
  background: var(--bg-tile);
  border: 1px solid var(--line-strong);
  border-radius: var(--r-sm);
  cursor: pointer;
  transition: background 0.15s var(--ease), border-color 0.15s var(--ease);
}
.btn:hover:not(:disabled) { background: var(--bg-hover); }
.btn:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.btn:disabled { opacity: 0.45; cursor: not-allowed; }
.btn--primary { color: var(--accent-ink); background: var(--accent); border-color: var(--accent); }
.btn--primary:hover:not(:disabled) { filter: brightness(1.08); background: var(--accent); }
.btn--danger { color: var(--danger); border-color: var(--danger); }
.btn--danger:hover:not(:disabled) { background: color-mix(in srgb, var(--danger) 14%, transparent); }
.btn--ghost { background: transparent; }
.btn--sm { padding: 0.3rem 0.6rem; font-size: var(--step--1); }

/* --- فیلد --------------------------------------------------------------- */
.fields { display: grid; gap: var(--gap); }
@media (min-width: 46rem) { .fields { grid-template-columns: 1fr 1fr; } }
.field--wide { grid-column: 1 / -1; }

.field { display: grid; gap: 0.3rem; }
.field__label { font-size: var(--step--1); color: var(--ink-muted); }
.field__hint  { font-size: var(--step--1); color: var(--ink-faint); }
.field__err   { font-size: var(--step--1); color: var(--danger); }
.field__warn  { font-size: var(--step--1); color: var(--warn); }
.field__row   { display: flex; gap: 0.4rem; align-items: center; }
.field__row > .input { flex: 1 1 auto; min-width: 0; }

.input, .select {
  width: 100%;
  padding: 0.5rem 0.65rem;
  font: inherit;
  font-size: var(--step--1);
  color: var(--ink);
  background: var(--bg-sunken);
  border: 1px solid var(--line);
  border-radius: var(--r-sm);
}
.input:focus-visible, .select:focus-visible {
  outline: 2px solid var(--accent);
  outline-offset: -1px;
  border-color: var(--accent);
}
.input--mono { font-family: var(--font-mono); }
.input[aria-invalid='true'] { border-color: var(--danger); }

.switch { display: flex; gap: 0.55rem; align-items: center; cursor: pointer; }
.switch input { width: 1.05rem; height: 1.05rem; accent-color: var(--accent); }

/* --- ردیف‌های پورت ------------------------------------------------------ */
.rows { display: grid; gap: 0.4rem; }
.row { display: flex; gap: 0.4rem; align-items: start; }
.row > .input { flex: 1 1 auto; font-family: var(--font-mono); }

/* --- نوار وضعیت -------------------------------------------------------- */
.bar {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
  align-items: center;
  padding: 0.7rem var(--pad);
  margin-block-end: var(--gap);
  font-size: var(--step--1);
  border: 1px solid var(--line);
  border-radius: var(--r-md);
  background: var(--bg-raised);
}
.bar--warn   { color: var(--warn);   border-color: color-mix(in srgb, var(--warn) 45%, var(--line)); }
.bar--ok     { color: var(--accent); border-color: color-mix(in srgb, var(--accent) 45%, var(--line)); }
.bar--danger { color: var(--danger); border-color: color-mix(in srgb, var(--danger) 45%, var(--line)); }
.bar > span { flex: 1 1 auto; }

/* --- نشان preflight ---------------------------------------------------- */
.chips { display: grid; gap: 0.4rem; margin-block-end: var(--gap); }
.chip {
  display: flex;
  gap: 0.5rem;
  align-items: baseline;
  padding: 0.45rem 0.7rem;
  font-size: var(--step--1);
  border-inline-start: 3px solid var(--line-strong);
  border-radius: var(--r-sm);
  background: var(--bg-tile);
}
.chip--error { border-inline-start-color: var(--danger); }
.chip--warn  { border-inline-start-color: var(--warn); }
.chip--info  { border-inline-start-color: var(--info); }

/* --- دیالوگ ------------------------------------------------------------ */
.dlg {
  max-width: 30rem;
  padding: var(--pad);
  color: var(--ink);
  background: var(--bg-raised);
  border: 1px solid var(--line-strong);
  border-radius: var(--r-lg);
}
.dlg::backdrop { background: rgb(0 0 0 / 0.55); }
.dlg__title { margin: 0 0 0.6rem; font-size: var(--step-1); }
.dlg__body  { margin: 0 0 var(--gap); font-size: var(--step--1); color: var(--ink-muted); }
.dlg__actions { display: flex; gap: 0.5rem; justify-content: flex-end; }

/* --- ویزارد ------------------------------------------------------------ */
.steps { display: flex; gap: 0.5rem; margin-block-end: var(--gap); font-size: var(--step--1); }
.step {
  display: flex;
  gap: 0.4rem;
  align-items: center;
  color: var(--ink-faint);
}
.step.is-active { color: var(--accent); }
.step.is-done   { color: var(--ink-muted); }
.step__n {
  display: grid;
  place-items: center;
  width: 1.5rem;
  height: 1.5rem;
  border: 1px solid currentColor;
  border-radius: 50%;
}
.picker { display: grid; gap: var(--gap); }
@media (min-width: 40rem) { .picker { grid-template-columns: 1fr 1fr; } }
.picker__opt {
  display: grid;
  gap: 0.35rem;
  padding: var(--pad);
  text-align: start;
  background: var(--bg-tile);
  border: 1px solid var(--line);
  border-radius: var(--r-md);
  cursor: pointer;
}
.picker__opt:hover { background: var(--bg-hover); }
.picker__opt.is-active { border-color: var(--accent); }
.picker__opt strong { font-size: var(--step-1); }
.picker__opt span { font-size: var(--step--1); color: var(--ink-muted); }

.review { font-family: var(--font-mono); font-size: var(--step--1); }
.review dt { color: var(--ink-muted); }

@media (prefers-reduced-motion: reduce) {
  .tab, .btn, .input, .select { transition: none; }
}
```

- [ ] **Step 7: در مرورگر بسنجش**

```bash
python web/devserver.py --port 8770
```

بعد با ابزار preview: `http://127.0.0.1:8770/` را باز کن، روی تب «تنظیمات» بزن و بسنج که (الف) hash به `#/settings` می‌رود، (ب) درخواست‌های `/stats` قطع می‌شوند، (ج) کارت سرویس وضعیت را نشان می‌دهد، (د) با کلیک روی «ری‌استارت» دیالوگ تأیید باز می‌شود، (ه) دکمه‌ی زبان هر دو تب را ترجمه می‌کند، (و) در `#/settings` با `?fresh=1` ویزارد می‌آید. کنسول باید خالی باشد.

- [ ] **Step 8: commit**

```bash
git add web/index.html web/assets/js/router.js web/assets/js/app.js web/assets/js/i18n.js web/assets/css/panel.css
git commit -m "پنل: دو تب، کارت سرویس، و پایه‌ی CSS و i18n تنظیمات"
```

---

## Task 7: فرم کانفیگ، preflight و نوار ری‌استارت

قلب کار: `settings.js` که فرم را از `SCHEMA` می‌سازد، فقط فیلدهای عوض‌شده را می‌فرستد، و ری‌استارت را به کاربر واگذار می‌کند.

**Files:**
- Create: `web/assets/js/settings.js`, `tests/web/dirty.test.mjs`
- Modify: `web/assets/js/app.js` (سیم‌کشی کارت سرویس و دیالوگ تأیید)

**Interfaces:**
- Consumes: از تسک ۵ → `config-schema.js` (`groupsFor`, `validateAll`, `validateField`, `validatePortRow`, `INSECURE_TRANSPORTS`), `api.js` (همه)؛ از تسک ۶ → `i18n.js` (`t`, `tf`), کلاس‌های CSS، `#settings-forms`, `#restart-bar`, `#confirm-dlg`
- Produces:
  - `settings.js` → `mountSettings()`, `diffValues(base, now) → {}` (خالص، تست‌شده جدا), `applyServiceState(svc)`, `apiMsg(err) → string`
  - `app.js` → `confirmAction(messageKey) → Promise<boolean>` (محلی، صادر نمی‌شود)، دکمه‌های کارت سرویس به `api.service` وصل، دیالوگ تأیید برای `restart|stop|disable`

- [ ] **Step 1: تست شکست‌خورده‌ی `diffValues` را بنویس**

`tests/web/dirty.test.mjs`:

```js
// فقط فیلدهای عوض‌شده فرستاده می‌شوند. اگر همه‌ی فیلدها فرستاده شوند،
// apply-config برای هر کلید یک sed می‌زند و «unchanged» را ۲۵ بار برمی‌گرداند
// — و بدتر، دو کاربر همزمان کار همدیگر را بازمی‌گردانند.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { diffValues } from '../../web/assets/js/settings.js';

test('بدون تغییر، خالی', () => {
  assert.deepEqual(diffValues({ a: 1, b: 'x' }, { a: 1, b: 'x' }), {});
});

test('فقط عوض‌شده‌ها', () => {
  assert.deepEqual(diffValues({ a: 1, b: 'x' }, { a: 2, b: 'x' }), { a: 2 });
});

test('کلید تازه هم تغییر است', () => {
  assert.deepEqual(diffValues({ a: 1 }, { a: 1, b: true }), { b: true });
});

test('آرایه‌ها عضو به عضو مقایسه می‌شوند', () => {
  assert.deepEqual(diffValues({ ports: ['443'] }, { ports: ['443'] }), {});
  assert.deepEqual(diffValues({ ports: ['443'] }, { ports: ['443', '80'] }),
                   { ports: ['443', '80'] });
  assert.deepEqual(diffValues({ ports: ['443', '80'] }, { ports: ['80', '443'] }),
                   { ports: ['80', '443'] }, 'ترتیب مهم است');
  assert.deepEqual(diffValues({ ports: [] }, { ports: [] }), {});
  assert.deepEqual(diffValues({ ports: ['443'] }, { ports: [] }), { ports: [] });
});

test('صفر و رشته‌ی خالی و false تغییر معتبرند', () => {
  assert.deepEqual(diffValues({ web_port: 2060 }, { web_port: 0 }), { web_port: 0 });
  assert.deepEqual(diffValues({ tls_cert: '/a' }, { tls_cert: '' }), { tls_cert: '' });
  assert.deepEqual(diffValues({ sniffer: true }, { sniffer: false }), { sniffer: false });
});

test('نوع مهم نیست وقتی مقدار یکی است', () => {
  assert.deepEqual(diffValues({ heartbeat: 40 }, { heartbeat: 40 }), {});
  assert.deepEqual(diffValues({ heartbeat: 40 }, { heartbeat: 41 }), { heartbeat: 41 });
});

test('کلید نبوده در now دست نمی‌خورد', () => {
  assert.deepEqual(diffValues({ a: 1, token: '********' }, { a: 1 }), {});
});
```

- [ ] **Step 2: تست را اجرا کن و ببین شکست می‌خورد**

```bash
node --test tests/web/dirty.test.mjs
```

انتظار: `ERR_MODULE_NOT_FOUND` — `settings.js` نیست.

- [ ] **Step 3: `web/assets/js/settings.js` را بنویس**

```js
// تب تنظیمات. فرم از config-schema.js ساخته می‌شود، پس این فایل هیچ کلید
// کانفیگی را به نام نمی‌شناسد جز جاهایی که رفتار ویژه لازم است (توکن، ports).
//
// سه قاعده‌ی رفتاری:
//  ۱. فقط فیلدهای عوض‌شده فرستاده می‌شوند (diffValues).
//  ۲. ری‌استارت هیچ‌وقت خودکار نیست — تونل زنده است و کاربران وصل‌اند.
//  ۳. توکن هیچ‌وقت خوانده نمی‌شود؛ فیلدش خالی شروع می‌شود و خالی ماندنش
//     یعنی «دست نزن».

import { groupsFor, validateAll, validateField, validatePortRow,
         INSECURE_TRANSPORTS } from './config-schema.js';
import * as api from './api.js';
import { t, tf } from './i18n.js';

const el = (id) => document.getElementById(id);

// ---------------------------------------------------------------- diff ----

const same = (a, b) => {
  if (Array.isArray(a) || Array.isArray(b)) {
    if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
    return a.every((v, i) => v === b[i]);
  }
  return a === b;
};

export function diffValues(base, now) {
  const out = {};
  for (const [k, v] of Object.entries(now)) {
    if (!same(base[k], v)) out[k] = v;
  }
  return out;
}

// ---------------------------------------------------------------- state --

let state = {
  side: null,
  base: {},        // آخرین مقدارهای خوانده‌شده از سرور
  tokenSet: false,
  mounted: false,
  busy: false,
};

// ------------------------------------------------------------- ساخت فرم --

function fieldNode(f) {
  const wrap = document.createElement('div');
  wrap.className = 'field' + (f.type === 'ports' ? ' field--wide' : '');
  wrap.dataset.key = f.key;

  const id = 'f-' + f.key;
  const label = document.createElement('label');
  label.className = 'field__label';
  label.htmlFor = id;
  label.textContent = t(f.i18n);
  if (f.type !== 'bool') wrap.append(label);

  if (f.type === 'bool') {
    const sw = document.createElement('label');
    sw.className = 'switch';
    const box = document.createElement('input');
    box.type = 'checkbox';
    box.id = id;
    const txt = document.createElement('span');
    txt.textContent = t(f.i18n);
    sw.append(box, txt);
    wrap.append(sw);
  } else if (f.type === 'enum') {
    const sel = document.createElement('select');
    sel.className = 'select';
    sel.id = id;
    for (const o of f.options) {
      const opt = document.createElement('option');
      opt.value = o;
      opt.textContent = o;
      sel.append(opt);
    }
    wrap.append(sel);
  } else if (f.type === 'ports') {
    const rows = document.createElement('div');
    rows.className = 'rows';
    rows.id = id;
    const add = document.createElement('button');
    add.type = 'button';
    add.className = 'btn btn--ghost btn--sm';
    add.textContent = t('cfg.ports.add');
    add.addEventListener('click', () => { addPortRow(rows, ''); markDirty(); });
    wrap.append(rows, add);
  } else if (f.type === 'token') {
    const row = document.createElement('div');
    row.className = 'field__row';
    const inp = document.createElement('input');
    inp.className = 'input input--mono';
    inp.id = id;
    inp.type = 'text';
    inp.autocomplete = 'off';
    inp.spellcheck = false;
    inp.placeholder = '••••••••';
    const gen = document.createElement('button');
    gen.type = 'button';
    gen.className = 'btn btn--ghost btn--sm';
    gen.textContent = t('cfg.token.generate');
    gen.addEventListener('click', async () => {
      try {
        const r = await api.newToken();
        inp.value = r.token;
        inp.dispatchEvent(new Event('input', { bubbles: true }));
      } catch (e) { flash(apiMsg(e), 'danger'); }
    });
    const copy = document.createElement('button');
    copy.type = 'button';
    copy.className = 'btn btn--ghost btn--sm';
    copy.textContent = t('cfg.token.copy');
    copy.addEventListener('click', async () => {
      if (!inp.value) return;
      try {
        await navigator.clipboard.writeText(inp.value);
        copy.textContent = t('cfg.token.copied');
        setTimeout(() => { copy.textContent = t('cfg.token.copy'); }, 1500);
      } catch { /* بی‌اجازه یا http — بی‌صدا رد شو */ }
    });
    row.append(inp, gen, copy);
    wrap.append(row);
  } else {
    const inp = document.createElement('input');
    inp.className = 'input' + (f.mono ? ' input--mono' : '');
    inp.id = id;
    inp.type = f.type === 'int' ? 'number' : 'text';
    if (f.type === 'int') { inp.min = String(f.min); inp.max = String(f.max); }
    inp.autocomplete = 'off';
    inp.spellcheck = false;
    wrap.append(inp);
  }

  const hint = t(f.i18n + '.hint');
  if (hint !== f.i18n + '.hint') {
    const h = document.createElement('p');
    h.className = 'field__hint';
    h.textContent = hint;
    wrap.append(h);
  }

  const err = document.createElement('p');
  err.className = 'field__err';
  err.hidden = true;
  err.id = id + '-err';
  wrap.append(err);

  const warn = document.createElement('p');
  warn.className = 'field__warn';
  warn.hidden = true;
  warn.dataset.role = 'warn';
  wrap.append(warn);

  return wrap;
}

function addPortRow(rows, value) {
  const row = document.createElement('div');
  row.className = 'row';
  const inp = document.createElement('input');
  inp.className = 'input';
  inp.type = 'text';
  inp.value = value;
  inp.placeholder = '443=1.1.1.1:5201';
  inp.autocomplete = 'off';
  inp.spellcheck = false;
  inp.setAttribute('aria-label', t('cfg.ports'));
  const del = document.createElement('button');
  del.type = 'button';
  del.className = 'btn btn--ghost btn--sm';
  del.textContent = t('cfg.ports.remove');
  del.addEventListener('click', () => { row.remove(); markDirty(); });
  row.append(inp, del);
  rows.append(row);
  return inp;
}

function buildForm(side) {
  const host = el('settings-forms');
  host.textContent = '';

  const chips = document.createElement('div');
  chips.className = 'chips';
  chips.id = 'pf-chips';
  host.append(chips);

  for (const g of groupsFor(side)) {
    const card = document.createElement('article');
    card.className = 'card';
    const h = document.createElement('h2');
    h.className = 'card__title';
    h.textContent = t('cfg.' + g.group);
    const fields = document.createElement('div');
    fields.className = 'fields';
    for (const f of g.fields) fields.append(fieldNode(f));
    card.append(h, fields);
    host.append(card);
  }

  const actions = document.createElement('div');
  actions.className = 'card__actions';
  const save = document.createElement('button');
  save.type = 'button';
  save.className = 'btn btn--primary';
  save.id = 'cfg-save';
  save.textContent = t('save.save');
  const discard = document.createElement('button');
  discard.type = 'button';
  discard.className = 'btn btn--ghost';
  discard.id = 'cfg-discard';
  discard.textContent = t('save.discard');
  actions.append(save, discard);
  host.append(actions);

  save.addEventListener('click', onSave);
  discard.addEventListener('click', () => { fillForm(state.base); markDirty(); });

  host.addEventListener('input', markDirty);
  host.addEventListener('change', markDirty);
}

// ----------------------------------------------------------- پر و خواندن --

function fillForm(values) {
  for (const f of groupsFor(state.side).flatMap((g) => g.fields)) {
    const node = el('f-' + f.key);
    if (!node) continue;
    if (f.type === 'bool') node.checked = values[f.key] === true;
    else if (f.type === 'ports') {
      node.textContent = '';
      for (const row of (values[f.key] || [])) addPortRow(node, row);
    } else if (f.type === 'token') node.value = '';   // هیچ‌وقت پر نمی‌شود
    else node.value = values[f.key] === undefined || values[f.key] === null
      ? '' : String(values[f.key]);
  }
}

function readForm() {
  const out = {};
  for (const f of groupsFor(state.side).flatMap((g) => g.fields)) {
    const node = el('f-' + f.key);
    if (!node) continue;
    if (f.type === 'bool') out[f.key] = node.checked;
    else if (f.type === 'ports') {
      out[f.key] = Array.from(node.querySelectorAll('input'))
        .map((i) => i.value.trim())
        .filter((v) => v !== '');
    } else out[f.key] = node.value;
  }
  return out;
}

// ---------------------------------------------------------- اعتبارسنجی --

function showFieldError(key, code, params) {
  const wrap = document.querySelector(`.field[data-key="${key}"]`);
  if (!wrap) return;
  const err = wrap.querySelector('.field__err');
  err.textContent = code ? tf(code, params) : '';
  err.hidden = !code;
  const input = wrap.querySelector('input, select');
  if (input) {
    if (code) {
      input.setAttribute('aria-invalid', 'true');
      input.setAttribute('aria-describedby', input.id + '-err');
    } else {
      input.removeAttribute('aria-invalid');
      input.removeAttribute('aria-describedby');
    }
  }
}

function clearErrors() {
  for (const wrap of document.querySelectorAll('.field[data-key]')) {
    showFieldError(wrap.dataset.key, null);
  }
  for (const row of document.querySelectorAll('.row > .input')) {
    row.removeAttribute('aria-invalid');
  }
}

// ردیف‌های پورت کلید مشترک دارند، پس خطا را روی خود ردیف هم نشان بده.
function markBadPortRows() {
  const rows = el('f-ports');
  if (!rows) return;
  for (const inp of rows.querySelectorAll('input')) {
    const v = inp.value.trim();
    const bad = v !== '' && !validatePortRow(v).ok;
    if (bad) inp.setAttribute('aria-invalid', 'true');
    else inp.removeAttribute('aria-invalid');
  }
}

// هشدارهای غیرمسدودکننده: پروتکل بی‌رمز، پورت خالی.
function softWarnings(values) {
  const tw = document.querySelector('.field[data-key="transport"] [data-role="warn"]');
  if (tw) {
    const bad = INSECURE_TRANSPORTS.includes(values.transport);
    tw.textContent = bad ? t('cfg.transport.insecure') : '';
    tw.hidden = !bad;
  }
  const pw = document.querySelector('.field[data-key="ports"] [data-role="warn"]');
  if (pw) {
    const empty = (values.ports || []).length === 0;
    pw.textContent = empty ? t('cfg.ports.empty') : '';
    pw.hidden = !empty;
  }
}

function markDirty() {
  const now = readForm();
  softWarnings(now);
  markBadPortRows();
  const changed = diffValues(state.base, now);
  const tokenTyped = (now.token || '') !== '';
  const n = Object.keys(changed).length + (tokenTyped ? 1 : 0);
  const save = el('cfg-save');
  if (save) save.disabled = state.busy || n === 0;
  const discard = el('cfg-discard');
  if (discard) discard.disabled = state.busy || n === 0;
}

// ------------------------------------------------------------- ذخیره --

async function onSave() {
  if (state.busy) return;
  clearErrors();
  const now = readForm();
  const v = validateAll(state.side, now);
  if (!v.ok) {
    for (const [key, e] of Object.entries(v.errors)) {
      showFieldError(key, e.code, e.params);
    }
    markBadPortRows();
    flash(t('save.hasErrors'), 'danger');
    const first = document.querySelector('[aria-invalid="true"]');
    if (first) first.focus();
    return;
  }

  // diff روی مقدارهای خام فرم است (همان جنس base)، ولی چیزی که فرستاده
  // می‌شود مقدار تایپ‌شده است — وگرنه heartbeat به‌صورت رشته می‌رفت و
  // apply-config عدد می‌خواهد.
  const changedKeys = Object.keys(diffValues(state.base, now));
  const payload = {};
  for (const k of changedKeys) {
    if (k in v.values) payload[k] = v.values[k];
  }
  // توکن جدا: از base نمی‌آید، پس diff آن را نمی‌بیند.
  if (v.values.token) payload.token = v.values.token;
  if (Object.keys(payload).length === 0) { flash(t('save.nothing'), 'ok'); return; }

  setBusy(true, t('save.saving'));
  try {
    const r = await api.putConfig(state.side, payload);
    // base را از سرور بازخوان، نه از فرم — تا اگر CLI چیزی را نرمال کرد
    // (مثل عدد با صفر پیشرو) فرم با فایل هم‌خوان بماند.
    await load();
    if (r.restartNeeded) showRestartBar();
    else flash(t('save.saved'), 'ok');
    refreshPreflight();
  } catch (e) {
    flash(apiMsg(e), 'danger');
  } finally {
    setBusy(false);
  }
}

function setBusy(on, label) {
  state.busy = on;
  const save = el('cfg-save');
  if (save) {
    save.disabled = on;
    save.textContent = on ? (label || t('save.saving')) : t('save.save');
  }
  for (const b of document.querySelectorAll('#card-service .btn')) b.disabled = on;
  if (!on) markDirty();
}

// -------------------------------------------------------- نوار وضعیت --

function flash(msg, kind) {
  const bar = el('flash-bar') || (() => {
    const b = document.createElement('div');
    b.className = 'bar';
    b.id = 'flash-bar';
    b.setAttribute('role', 'status');
    el('view-settings').prepend(b);
    return b;
  })();
  bar.className = 'bar bar--' + (kind || 'ok');
  bar.textContent = msg;
  bar.hidden = false;
  clearTimeout(flash._t);
  // پیام خطا می‌ماند؛ پیام موفقیت خودش می‌رود.
  if (kind !== 'danger') flash._t = setTimeout(() => { bar.hidden = true; }, 4000);
}

function showRestartBar() {
  const bar = el('restart-bar');
  bar.hidden = false;
  bar.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
}

export function apiMsg(e) {
  if (e && e.name === 'ApiError') {
    const known = t('api.' + e.code);
    const head = known === 'api.' + e.code ? t('api.cli_failed') : known;
    return e.detail ? head + ' — ' + e.detail : head;
  }
  return String((e && e.message) || e);
}

// ---------------------------------------------------------- preflight --

async function refreshPreflight() {
  const box = el('pf-chips');
  if (!box) return;
  try {
    const r = await api.preflight(state.side);
    box.textContent = '';
    if (!r.checks.length) {
      const ok = document.createElement('div');
      ok.className = 'chip';
      ok.textContent = t('pf.ok');
      box.append(ok);
      return;
    }
    const rank = { error: 0, warn: 1, info: 2 };
    for (const c of [...r.checks].sort((a, b) => rank[a.level] - rank[b.level])) {
      const chip = document.createElement('div');
      chip.className = 'chip chip--' + c.level;
      chip.textContent = tf(c.id, c.params);
      box.append(chip);
    }
  } catch {
    box.textContent = '';   // preflight اختیاری است — نبودش صفحه را نمی‌شکند
  }
}

// ------------------------------------------------------ وضعیت سرویس --

export function applyServiceState(svc) {
  el('svc-active').textContent = svc.active || '—';
  el('svc-enabled').textContent = svc.enabled || '—';
  const on = svc.active === 'active';
  const q = (a) => document.querySelector(`#card-service [data-action="${a}"]`);
  if (q('start')) q('start').disabled = on;
  if (q('stop')) q('stop').disabled = !on;
  if (q('enable')) q('enable').disabled = svc.enabled === 'enabled';
  if (q('disable')) q('disable').disabled = svc.enabled !== 'enabled';
}

// ------------------------------------------------------------ بارگذاری --

async function load() {
  const st = await api.getState();
  state.side = st.side ||
    (st.installed.server ? 'server' : st.installed.client ? 'client' : null);
  if (!state.side) throw new api.ApiError('not_installed', '', 0);
  applyServiceState(st.service || {});

  const cfg = await api.getConfig(state.side);
  state.tokenSet = cfg.tokenSet === true;
  // توکن ماسک‌شده هیچ‌وقت وارد base نمی‌شود، وگرنه diff آن را «تغییر» می‌دید.
  state.base = normalizeBase(cfg.values);
  fillForm(state.base);
  markDirty();
}

// base باید عیناً همان چیزی باشد که readForm بعد از fillForm می‌دهد، وگرنه
// diff از اولین لحظه چند فیلد را «عوض‌شده» می‌بیند و دکمه‌ی ذخیره بی‌دلیل
// فعال می‌ماند. دو ناهم‌خوانی واقعی: کلید نبوده در فایل (undefined در برابر
// رشته‌ی خالی)، و عددی که فرم به رشته برمی‌گرداند.
function normalizeBase(values) {
  const out = {};
  for (const f of groupsFor(state.side).flatMap((g) => g.fields)) {
    if (f.key === 'token') continue;   // هیچ‌وقت در base نمی‌نشیند
    const v = values[f.key];
    if (f.type === 'bool') out[f.key] = v === true;
    else if (f.type === 'ports') out[f.key] = Array.isArray(v) ? v.map(String) : [];
    else out[f.key] = v === undefined || v === null ? '' : String(v);
  }
  return out;
}

// هر بار که تب باز می‌شود صدا زده می‌شود، پس باید بی‌خطر تکرارشدنی باشد:
// فرم فقط یک بار ساخته می‌شود و بعدش فقط مقدارها تازه می‌شوند.
export async function mountSettings() {
  try {
    if (!state.mounted) {
      const st = await api.getState();
      const side = st.side ||
        (st.installed.server ? 'server' : st.installed.client ? 'client' : null);
      if (!side) { flash(t('api.not_installed'), 'warn'); return; }
      state.side = side;
      buildForm(side);
      state.mounted = true;
    }
    await load();
    refreshPreflight();
    if (!state.tokenSet) flash(t('cfg.token.unset'), 'warn');
  } catch (e) {
    flash(apiMsg(e), 'danger');
  }
}
```

- [ ] **Step 4: تست را اجرا کن و ببین پاس می‌شود**

```bash
node --test tests/web/
```

انتظار: تست‌های `dirty.test.mjs` و `config-schema.test.mjs` هر دو پاس. `settings.js` در Node بارگذاری می‌شود چون `document` فقط داخل تابع‌ها لمس می‌شود، نه در سطح ماژول — این عمدی است و شرط تست‌شدن `diffValues` بدون DOM.

- [ ] **Step 5: کارت سرویس و دیالوگ تأیید را در `app.js` سیم‌کشی کن**

قلاب `let mountSettings = () => {};` که تسک ۶ گذاشت را **پاک کن** و جایش این
import را بگذار (قلاب `mountWizard` سر جایش می‌ماند تا تسک ۸):

```js
import { mountSettings, applyServiceState, apiMsg } from './settings.js';

// ری‌استارت و توقف و غیرفعال‌کردن، هر سه اتصال‌های زنده را لمس می‌کنند.
// هیچ‌کدام بدون تأیید صریح اجرا نمی‌شوند.
const CONFIRM = {
  restart: 'svc.confirmRestart',
  stop: 'svc.confirmStop',
  disable: 'svc.confirmDisable',
};

function confirmAction(msgKey) {
  const dlg = document.getElementById('confirm-dlg');
  document.getElementById('confirm-body').textContent = t(msgKey);
  return new Promise((resolve) => {
    const done = (v) => {
      dlg.close();
      yes.removeEventListener('click', onYes);
      no.removeEventListener('click', onNo);
      resolve(v);
    };
    const yes = document.getElementById('confirm-yes');
    const no = document.getElementById('confirm-no');
    const onYes = () => done(true);
    const onNo = () => done(false);
    yes.addEventListener('click', onYes);
    no.addEventListener('click', onNo);
    dlg.addEventListener('cancel', onNo, { once: true });
    dlg.showModal();
    no.focus();
  });
}

for (const btn of document.querySelectorAll('#card-service [data-action]')) {
  btn.addEventListener('click', async () => {
    const action = btn.dataset.action;
    if (CONFIRM[action] && !(await confirmAction(CONFIRM[action]))) return;
    const buttons = document.querySelectorAll('#card-service .btn');
    for (const b of buttons) b.disabled = true;
    try {
      const st = await getState();
      const side = st.side ||
        (st.installed && st.installed.server ? 'server' : 'client');
      await service(side, action);
      document.getElementById('restart-bar').hidden = true;
    } catch (e) {
      alert(apiMsg(e));
    } finally {
      for (const b of buttons) b.disabled = false;
      // وضعیت را از سرور بخوان، نه از حدس — systemd می‌تواند شروع را رد کند.
      // در مسیر خطا هم لازم است: ممکن است کار نیمه انجام شده باشد.
      const fresh = await getState().catch(() => ({}));
      applyServiceState(fresh.service || {});
    }
  });
}

document.getElementById('restart-now').addEventListener('click', () => {
  document.querySelector('#card-service [data-action="restart"]').click();
});
```

`import { getState, service } from './api.js';` و `import { t } from './i18n.js';` باید بالای فایل باشند (`t` معمولاً هست).

- [ ] **Step 6: در مرورگر بسنجش — مسیر خوش‌بینانه**

```bash
python web/devserver.py --port 8770
```

با ابزار preview روی `http://127.0.0.1:8770/#/settings`:
1. سه کارت (تونل، پورت‌ها، پیشرفته) دیده می‌شوند و مقدارها پر شده‌اند.
2. دکمه‌ی «ذخیره» **غیرفعال** است (چیزی عوض نشده).
3. `log_level` را به `info` عوض کن → ذخیره فعال می‌شود.
4. ذخیره بزن → نوار زرد «برای اعمال، ری‌استارت لازم است» می‌آید.
5. «ری‌استارت کن» → دیالوگ تأیید با متن قطع اتصال‌ها.
6. «انصراف» → هیچ درخواستی به `/api/service` نمی‌رود (با `preview_network` بسنج).
7. یک ردیف پورت اضافه کن و `2100-2000` بگذار → ذخیره خطای «ابتدای بازه از انتهایش بزرگ‌تر است» می‌دهد و روی همان ردیف `aria-invalid` می‌گذارد.
8. `transport` را `tcp` کن → هشدار «رمزنگاری ندارد» زیر فیلد می‌آید ولی ذخیره را مسدود نمی‌کند.
9. «تولید» توکن بزن → ۶۴ نویسه پر می‌شود و ذخیره فعال می‌شود.
10. «برگرداندن تغییرها» → فرم به حالت اول و ذخیره غیرفعال.

کنسول باید خالی باشد.

- [ ] **Step 7: در مرورگر بسنجش — مسیر خطا**

روی `http://127.0.0.1:8770/#/settings?apifail=1`: یک فیلد را عوض کن و ذخیره بزن. انتظار: نوار قرمز با متن `دستور اجرا نشد. — transport نامعتبر: «quic»` که **می‌ماند** و خودش نمی‌رود، و فرم مقدارهای تایپ‌شده را از دست نمی‌دهد.

- [ ] **Step 8: دسترس‌پذیری را بسنج**

با `preview_snapshot` بسنج که هر ورودی `<label>` مرتبط دارد، فیلد خطادار `aria-invalid="true"` و `aria-describedby` می‌گیرد، و نوارها `role="status"` دارند. با `preview_eval` گشت کلید بزن:

```js
document.querySelectorAll('#view-settings input, #view-settings select, #view-settings button')
  .length
```

و بسنج که هیچ عنصر تعاملی `tabindex="-1"` ندارد:

```js
document.querySelectorAll('#view-settings [tabindex="-1"]').length   // 0
```

- [ ] **Step 9: commit**

```bash
git add web/assets/js/settings.js web/assets/js/app.js tests/web/dirty.test.mjs
git commit -m "پنل: فرم کانفیگ با اعتبارسنجی زنده، preflight و ری‌استارت دستی"
```

---

## Task 8: ویزارد سرور خام

سه گام از سرور خالی تا سرویس نصب‌شده. تنها مسیری که کاربر بدون CLI می‌تواند تونل را از صفر بالا بیاورد.

**Files:**
- Create: `web/assets/js/wizard.js`
- Modify: `web/assets/js/app.js` (ورود به ویزارد وقتی هیچ سمتی نصب نیست)

**Interfaces:**
- Consumes: از تسک ۵ → `config-schema.js`, `api.js`؛ از تسک ۶ → `#view-wizard`, `.steps`, `.picker`, `.review`؛ از تسک ۷ → `apiMsg`
- Produces: `wizard.js` → `mountWizard()`

- [ ] **Step 1: `web/assets/js/wizard.js` را بنویس**

```js
// ویزارد سرور خام. وقتی /api/state می‌گوید هیچ سمتی نصب نیست، جای دو تب
// این می‌آید.
//
// عمداً کوچک است: فقط فیلدهای لازم برای «تونل بالا می‌آید» را می‌پرسد و
// بقیه را به پیش‌فرض‌های configs/*.toml می‌سپارد. تنظیم دقیق کار تب
// تنظیمات است، بعد از نصب.

import { validateField, SCHEMA, TRANSPORTS } from './config-schema.js';
import * as api from './api.js';
import { t, tf } from './i18n.js';
import { apiMsg } from './settings.js';

const field = (key) => SCHEMA.find((f) => f.key === key);

// حداقل فیلدهای هر سمت. توکن در هر دو سمت لازم است چون بدون آن تونل بالا
// نمی‌آید، و ما CHANGE_ME را عمداً به‌عنوان توکن نمی‌پذیریم.
const NEEDED = {
  server: ['bind_addr', 'transport', 'token', 'ports'],
  client: ['remote_addr', 'transport', 'token'],
};

const DEFAULTS = {
  server: { bind_addr: '0.0.0.0:3080', transport: 'tcpmux', ports: ['443'] },
  client: { remote_addr: '', transport: 'tcpmux' },
};

let st = { step: 1, side: null, values: {}, busy: false };

const host = () => document.getElementById('view-wizard');

function h(tag, cls, text) {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined) n.textContent = text;
  return n;
}

function stepsBar() {
  const bar = h('div', 'steps');
  ['wz.step1', 'wz.step2', 'wz.step3'].forEach((key, i) => {
    const n = i + 1;
    const s = h('div', 'step' + (n === st.step ? ' is-active' : n < st.step ? ' is-done' : ''));
    s.append(h('span', 'step__n', String(n)), h('span', null, t(key)));
    bar.append(s);
  });
  return bar;
}

function render() {
  const box = host();
  box.hidden = false;
  box.textContent = '';

  const card = h('article', 'card');
  card.append(h('h2', 'card__title', t('wz.title')));
  card.append(stepsBar());

  if (st.step === 1) renderPick(card);
  else if (st.step === 2) renderForm(card);
  else renderReview(card);

  box.append(card);
}

// --- گام ۱: نقش ---------------------------------------------------------

function renderPick(card) {
  card.append(h('p', 'field__hint', t('wz.intro')));
  const pick = h('div', 'picker');
  for (const side of ['server', 'client']) {
    const b = h('button', 'picker__opt' + (st.side === side ? ' is-active' : ''));
    b.type = 'button';
    b.append(h('strong', null, t('wz.' + side)), h('span', null, t('wz.' + side + 'Desc')));
    b.addEventListener('click', () => {
      st.side = side;
      st.values = { ...DEFAULTS[side] };
      st.step = 2;
      render();
    });
    pick.append(b);
  }
  card.append(pick);
}

// --- گام ۲: فیلدها ------------------------------------------------------

function renderForm(card) {
  const fields = h('div', 'fields');
  for (const key of NEEDED[st.side]) {
    const f = field(key);
    const wrap = h('div', 'field' + (key === 'ports' ? ' field--wide' : ''));
    wrap.dataset.key = key;
    const id = 'wz-' + key;

    const label = h('label', 'field__label', t(f.i18n));
    label.htmlFor = id;
    wrap.append(label);

    if (f.type === 'enum') {
      const sel = h('select', 'select');
      sel.id = id;
      for (const o of TRANSPORTS) {
        const opt = h('option', null, o);
        opt.value = o;
        if (st.values[key] === o) opt.selected = true;
        sel.append(opt);
      }
      wrap.append(sel);
    } else if (f.type === 'ports') {
      const inp = h('input', 'input input--mono');
      inp.id = id;
      inp.type = 'text';
      inp.value = (st.values.ports || []).join(', ');
      inp.placeholder = '443, 8443=443';
      wrap.append(inp);
    } else if (f.type === 'token') {
      const row = h('div', 'field__row');
      const inp = h('input', 'input input--mono');
      inp.id = id;
      inp.type = 'text';
      inp.value = st.values.token || '';
      inp.autocomplete = 'off';
      inp.spellcheck = false;
      const gen = h('button', 'btn btn--ghost btn--sm', t('cfg.token.generate'));
      gen.type = 'button';
      gen.addEventListener('click', async () => {
        try { inp.value = (await api.newToken()).token; }
        catch (e) { showErr(key, null, apiMsg(e)); }
      });
      row.append(inp, gen);
      wrap.append(row);
      // توکن در ویزارد لازم است، پس یادآوری کن که سمت دیگر هم همین را بخواهد.
      wrap.append(h('p', 'field__hint', t('wz.tokenNote')));
    } else {
      const inp = h('input', 'input' + (f.mono ? ' input--mono' : ''));
      inp.id = id;
      inp.type = 'text';
      inp.value = st.values[key] || '';
      inp.autocomplete = 'off';
      inp.spellcheck = false;
      wrap.append(inp);
    }

    const hint = t(f.i18n + '.hint');
    if (hint !== f.i18n + '.hint') wrap.append(h('p', 'field__hint', hint));
    const err = h('p', 'field__err');
    err.hidden = true;
    err.id = id + '-err';
    wrap.append(err);
    fields.append(wrap);
  }
  card.append(fields);

  const actions = h('div', 'card__actions');
  const back = h('button', 'btn btn--ghost', t('wz.back'));
  back.type = 'button';
  back.addEventListener('click', () => { st.step = 1; render(); });
  const next = h('button', 'btn btn--primary', t('wz.next'));
  next.type = 'button';
  next.addEventListener('click', () => { if (collect()) { st.step = 3; render(); } });
  actions.append(back, next);
  card.append(actions);
}

function showErr(key, code, raw) {
  const wrap = document.querySelector(`#view-wizard .field[data-key="${key}"]`);
  if (!wrap) return;
  const err = wrap.querySelector('.field__err');
  err.textContent = raw || (code ? tf(code.code, code.params) : '');
  err.hidden = !err.textContent;
  const input = wrap.querySelector('input, select');
  if (input) {
    if (err.textContent) {
      input.setAttribute('aria-invalid', 'true');
      input.setAttribute('aria-describedby', input.id + '-err');
    } else {
      input.removeAttribute('aria-invalid');
      input.removeAttribute('aria-describedby');
    }
  }
}

function collect() {
  let ok = true;
  const out = {};
  for (const key of NEEDED[st.side]) {
    const f = field(key);
    const node = document.getElementById('wz-' + key);
    showErr(key, null, '');
    let raw = node.value;
    if (key === 'ports') {
      raw = raw.split(',').map((s) => s.trim()).filter((s) => s !== '');
    }
    const r = validateField(f, raw);
    if (!r.ok) { showErr(key, r); ok = false; continue; }
    // در ویزارد توکن اجباری است: خالی بودنش یعنی تونل بالا نمی‌آید.
    if (key === 'token' && r.value === undefined) {
      showErr(key, { code: 'err.tokenShort', params: { min: 32 } });
      ok = false;
      continue;
    }
    out[key] = r.value;
  }
  if (ok) st.values = { ...st.values, ...out };
  else {
    const first = document.querySelector('#view-wizard [aria-invalid="true"]');
    if (first) first.focus();
  }
  return ok;
}

// --- گام ۳: بازبینی و نصب ----------------------------------------------

function renderReview(card) {
  card.append(h('p', 'field__hint', t('wz.review')));
  const dl = h('dl', 'card__facts review');
  dl.append(h('dt', null, t('wz.step1')), h('dd', null, t('wz.' + st.side)));
  for (const key of NEEDED[st.side]) {
    const v = st.values[key];
    dl.append(
      h('dt', null, t(field(key).i18n)),
      h('dd', null, key === 'token' ? v
        : Array.isArray(v) ? (v.join(', ') || '—') : String(v || '—')),
    );
  }
  card.append(dl);

  const status = h('div', 'bar');
  status.id = 'wz-status';
  status.hidden = true;
  status.setAttribute('role', 'status');
  card.append(status);

  const actions = h('div', 'card__actions');
  const back = h('button', 'btn btn--ghost', t('wz.back'));
  back.type = 'button';
  back.addEventListener('click', () => { st.step = 2; render(); });
  const run = h('button', 'btn btn--primary', t('wz.installNow'));
  run.type = 'button';
  run.id = 'wz-run';
  run.addEventListener('click', () => install(run, status));
  actions.append(back, run);
  card.append(actions);
}

async function install(btn, status) {
  if (st.busy) return;
  st.busy = true;
  btn.disabled = true;
  btn.textContent = t('wz.installing');
  status.hidden = false;
  status.className = 'bar';
  status.textContent = t('wz.installing');
  try {
    await api.install(st.side, st.values);
    status.className = 'bar bar--ok';
    status.textContent = t('wz.done');
    // نصب سرویس را روشن نمی‌کند — همان قاعده: هیچ چیز خودکار شروع نمی‌شود.
    // یک بازخوانی، تب‌ها را می‌آورد و کاربر از کارت سرویس شروع می‌کند.
    setTimeout(() => window.location.reload(), 1200);
  } catch (e) {
    status.className = 'bar bar--danger';
    status.textContent = apiMsg(e);
    btn.disabled = false;
    btn.textContent = t('wz.installNow');
  } finally {
    st.busy = false;
  }
}

export function mountWizard() {
  st = { step: 1, side: null, values: {}, busy: false };
  render();
}
```

- [ ] **Step 2: قلاب `mountWizard` را در `app.js` با import واقعی عوض کن**

خط `let mountWizard = () => {};` که تسک ۶ گذاشت را پاک کن و بالای فایل:

```js
import { mountWizard } from './wizard.js';
```

بعد از این تسک هیچ قلاب خالی‌ای در `app.js` نمانده. بسنج:

```bash
grep -n 'let mount' web/assets/js/app.js
```

انتظار: خروجی خالی.

- [ ] **Step 3: در مرورگر بسنجش**

```bash
python web/devserver.py --port 8770
```

روی `http://127.0.0.1:8770/?fresh=1`:
1. تب‌ها دیده نمی‌شوند، ویزارد گام ۱ می‌آید.
2. «سرور» را انتخاب کن → گام ۲ با `bind_addr = 0.0.0.0:3080` و `ports = 443` پر است.
3. توکن را خالی بگذار و «بعدی» بزن → خطای «دست‌کم ۳۲ نویسه» و فوکوس روی همان فیلد.
4. «تولید» بزن → پر می‌شود، «بعدی» → گام ۳ با جدول بازبینی.
5. «قبلی» → گام ۲ با مقدارها **دست‌نخورده** (این تست حالت است، آسان می‌شکند).
6. «نصب و راه‌اندازی» → نوار سبز و بازخوانی؛ بعد از بازخوانی تب‌ها می‌آیند چون mock حالا `installed.server = true` است.
7. با `?fresh=1` و «کلاینت»: `remote_addr` خالی است و `SERVER_IP:3080` رد می‌شود، و فیلد `ports` وجود ندارد.
8. `preview_network` بسنج: در گام ۱ و ۲ هیچ درخواست نوشتنی نمی‌رود.

- [ ] **Step 4: تست حالت ویزارد را با گشت دستی تکمیل کن**

با `preview_resize` روی `mobile` بسنج که `.picker` تک‌ستونی می‌شود، `.steps` نمی‌ریزد، و `.field__row` (توکن + دکمه‌ی تولید) سرریز افقی نمی‌سازد:

```js
document.documentElement.scrollWidth <= document.documentElement.clientWidth
```

انتظار: `true`. بعد `preview_resize` به `desktop` برگردان.

- [ ] **Step 5: زبان را بسنج**

دکمه‌ی زبان را بزن و بسنج که کل ویزارد به انگلیسی می‌رود و هیچ متنی به شکل کلید خام (`wz.serverDesc`) دیده نمی‌شود:

```js
[...document.querySelectorAll('#view-wizard *')]
  .filter((n) => n.children.length === 0 && /^(wz|cfg|err|api)\./.test(n.textContent.trim()))
  .map((n) => n.textContent.trim())
```

انتظار: `[]`. (ویزارد بعد از `setLocale` باید `mountWizard()` را دوباره صدا بزند — اگر نمی‌زند، در `i18n` جای `applyDocumentLocale` یک `wizard:relocale` رویداد بفرست و در `wizard.js` گوش بده.)

- [ ] **Step 6: commit**

```bash
git add web/assets/js/wizard.js web/assets/js/app.js
git commit -m "پنل: ویزارد سه‌گامی راه‌اندازی برای سرور خام"
```

---

## Task 9: مستندات و آزمون سرتاسری روی نمونه‌ی جدا

آخرین تسک: مستندات، بعد یک نمونه‌ی کاملاً جدا روی همان سروری که تونل زنده دارد، و در پایان جمع‌کردن نمونه‌ی تست.

**هشدار مهم برای اجراکننده:** روی `62.60.193.137` یک تونل زنده با کاربران متصل هست. هیچ دستوری در این تسک نباید `farshub-server.service`، `/etc/farshub/server.toml`، پورت `3080`، پورت `2060`، یا سایت nginx `farshub-panel` را لمس کند. همه‌ی کارها با پیشوند `FARSHUB_*` و نام یونیت `farshub-test` انجام می‌شود. هر گام یک سنجش «تونل زنده دست‌نخورده» دارد.

**Files:**
- Modify: `docs/PANEL.md`, `docs/CLI.md`, `README.md`
- Create: `tests/e2e/README.md`

**Interfaces:**
- Consumes: همه‌ی تسک‌های ۱ تا ۸
- Produces: مستندات کاربر برای مسیر پنل، و یک دفترچه‌ی تست سرتاسری که قابل تکرار باشد

- [ ] **Step 1: `docs/PANEL.md` را به‌روز کن**

بخش تازه بعد از راه‌اندازی پنل، پیش از بخش عیب‌یابی:

```markdown
## تنظیم تونل از پنل

پنل به‌تنهایی فقط نمایش می‌دهد. برای اینکه از خود پنل هم بتوانید کانفیگ را
عوض کنید و سرویس را بالا و پایین ببرید، یک سرویس کوچک کنار آن نصب می‌شود:

```bash
sudo farshub api-up
```

این کار پنج چیز انجام می‌دهد:

| کار | جزئیات |
|---|---|
| کاربر بی‌ورود | `farshub-api` بدون شل و بدون خانه |
| سرویس | `farshub-api.service` روی `127.0.0.1:2061` — از بیرون سرور دیده نمی‌شود |
| sudoers | فهرست بسته‌ی دستورهای مجاز، با آرگومان ثابت |
| مسیر nginx | `location /api/` روی همان سایت پنل، پشت همان رمز |
| بازنویسی سایت | با `nginx -t` سنجیده می‌شود و در صورت خطا برمی‌گردد |

بعد از آن در پنل تب «تنظیمات» فعال می‌شود.

### چه چیزی از پنل قابل تغییر است

سه کارت: **تونل** (نشانی، پروتکل، توکن)، **پورت‌ها** (فقط سمت سرور)، و
**پیشرفته** (mux، بافرها، لاگ، آمار). هر فیلد پیش از فرستادن سنجیده می‌شود و
همان بازه‌هایی را می‌پذیرد که `farshub apply-config` می‌پذیرد.

**ری‌استارت هیچ‌وقت خودکار نیست.** بعد از ذخیره یک نوار زرد می‌گوید ری‌استارت
لازم است و شما دکمه‌اش را می‌زنید. دلیلش ساده است: ری‌استارت همه‌ی اتصال‌های
فعلی را قطع می‌کند و این تصمیم شماست، نه پنل.

### توکن

توکن هیچ‌وقت از سرور خوانده نمی‌شود — پنل فقط می‌داند «تنظیم شده» یا «نشده».
فیلدش همیشه خالی است و خالی ماندنش یعنی «دست نزن». دکمه‌ی «تولید» یک توکن
۶۴ نویسه‌ای می‌سازد؛ **عیناً همان** باید روی سمت دیگر تونل هم بنشیند.

### سرور خام

اگر روی سرور هیچ سمتی نصب نباشد، جای دو تب یک ویزارد سه‌گامی می‌آید: نقش،
تنظیم‌های پایه، بازبینی و نصب. برای رسیدن به آن روی سرور خام:

```bash
sudo farshub setup
```

این یعنی `install` + `panel-up` + `api-up` در یک دستور. بعدش پنل را باز کنید
و بقیه را از مرورگر ببرید جلو.

### مرز امنیتی

سرویس تنظیمات **خودش هیچ فایلی نمی‌نویسد**. هر کار ریشه‌ای از
`sudo farshub <زیردستور>` با آرگومان ثابت می‌گذرد و همان کدی اجرا می‌شود که
از خط فرمان اجرا می‌شد. بدترین پیامد یک باگ در این سرویس «یک کانفیگ خراب و
یک ری‌استارت» است، نه اجرای دلخواه دستور.

سرویس روی `127.0.0.1` گوش می‌دهد؛ تنها راه رسیدن به آن nginx است و nginx
همان `auth_basic` پنل را روی `/api/` هم می‌گذارد. برای برداشتنش:

```bash
sudo farshub api-down
```

پنل نمایشی سر جایش می‌ماند و تب تنظیمات غیرفعال می‌شود.

### هنوز روی HTTP است

رمز پنل و توکن تونل هر دو روی سیم به‌صورت متن ساده می‌روند. تا وقتی TLS
نگذاشته‌اید، پنل را از شبکه‌ی امن یا از تونل SSH باز کنید:

```bash
ssh -L 8088:127.0.0.1:8088 root@SERVER_IP
```
```

- [ ] **Step 2: `docs/CLI.md` را کامل کن**

بخش `apply-config` (که در تسک ۲ اضافه شد) باید نمونه‌ی خط فرمانی هم داشته باشد:

```markdown
### apply-config

مقدارهای کانفیگ را با اعتبارسنجی می‌نویسد. ورودی از stdin می‌آید، در دو شکل:

```bash
# شکل خط به خط
printf 'transport=tcpmux\nheartbeat=40\nports+=443\nports+=8443=443\n' \
  | sudo farshub apply-config server

# شکل JSON (اگر پایتون روی سرور باشد)
echo '{"transport":"tcpmux","ports":["443","8443=443"]}' \
  | sudo farshub apply-config server
```

خروجی، یک خط برای هر کلید:

```
changed transport
unchanged heartbeat
changed ports
```

هیچ کلیدی که در ورودی نباشد لمس نمی‌شود، و هیچ سرویسی خودش ری‌استارت
نمی‌شود. برای اعمال:

```bash
sudo farshub restart server
```

اعتبارسنجی پیش از نوشتن است و همه‌یا-هیچ: اگر یک کلید رد شود، فایل دست
نمی‌خورد. `ports=` (خالی) فهرست را پاک می‌کند.
```

و `README.md`: در جدول دستورها سه ردیف تازه (`api-up`, `api-down`, `setup`,
`apply-config`) و در بخش «راه‌اندازی سریع» یک مسیر تازه:

```markdown
### راه سوم: همه‌چیز با یک دستور، بقیه از مرورگر

```bash
sudo farshub setup
```

نصب + پنل + سرویس تنظیمات. بعدش پنل را باز کنید و تونل را از مرورگر کانفیگ
کنید. [آموزش پنل](docs/PANEL.md)
```

- [ ] **Step 3: دفترچه‌ی تست را بنویس**

`tests/e2e/README.md`:

```markdown
# آزمون سرتاسری روی نمونه‌ی جدا

این دفترچه روی سروری اجرا می‌شود که **تونل زنده دارد**. همه‌ی کارها در یک
نمونه‌ی کاملاً جدا انجام می‌شود و هیچ‌چیز نمونه‌ی زنده را لمس نمی‌کند.

## جدایی

| چیز | زنده | تست |
|---|---|---|
| مسیر کانفیگ | `/etc/farshub` | `/opt/fh-test/conf` |
| یونیت | `farshub-server.service` | `farshub-test-server.service` |
| پورت تونل | `3080` | `3990` |
| پورت آمار موتور | `2060` | `2062` |
| سرویس API | `2061` | `2063` |
| nginx | `farshub-panel` روی `8088` | `farshub-test` روی `8099` |

## متغیرها

روی سرور یک فایل محیط بساز و از این به بعد هر دستور را با `.` سوارش کن.
تکرار دستی متغیرها در هر خط، جایی که یکی جا بیفتد سراغ نمونه‌ی **زنده**
می‌رود — پس فایل، نه تکرار:

`/opt/fh-test/env.sh`:

```sh
export FARSHUB_CONF_DIR=/opt/fh-test/conf
export FARSHUB_LIBEXEC=/opt/fh-test/libexec
export FARSHUB_STATE_DIR=/opt/fh-test/state
export FARSHUB_LOG_DIR=/opt/fh-test/log
export FARSHUB_BIN_DIR=/opt/fh-test/bin
export FARSHUB_UNIT_PREFIX=farshub-test
export FARSHUB_SITE_NAME=farshub-test
export FARSHUB_HTPASSWD=/etc/nginx/farshub-test.htpasswd
export FH=/opt/fh-test/src/bin/farshub
```

`FARSHUB_BIN_DIR` از قلم نیفتد: بدونش `install` روی
`/usr/local/bin/farshub` **زنده** می‌نویسد و `api-up` اجرایی API تست را هم
همان‌جا می‌گذارد. `FARSHUB_UNIT_DIR` عمداً نیست — یونیت باید در
`/etc/systemd/system` باشد وگرنه `systemctl` نمی‌بیندش، و `UNIT_PREFIX` جدایی
را تأمین می‌کند.

و برای نمونه‌ی سوم (ویزارد) `/opt/fh-w/env.sh` با همان شکل ولی
`/opt/fh-w/*`، `FARSHUB_UNIT_PREFIX=farshub-w`، `FARSHUB_SITE_NAME=farshub-w`.

از این به بعد هر دستور تست این شکل را دارد:

```bash
ssh root@62.60.193.137 '. /opt/fh-test/env.sh && sh "$FH" status server'
```

## گام‌ها

هر گام با سنجش «زنده دست‌نخورده» تمام می‌شود:

```bash
systemctl is-active farshub-server nginx
systemctl show -p MainPID --value farshub-server    # باید همان PID اول بماند
ss -ltnp | grep -E ':(3080|2060|8088)\b'
```
```

- [ ] **Step 4: PID و وضعیت اولیه‌ی تونل زنده را ثبت کن**

```bash
ssh root@62.60.193.137 'systemctl show -p MainPID --value farshub-server; systemctl is-active farshub-server nginx; ss -ltn | grep -E ":(3080|2060|8088)"' 
```

خروجی را نگه دار. **هر گام بعدی با همین مقایسه می‌شود.** اگر PID عوض شد یا
یکی از پورت‌ها رفت، فوراً متوقف شو و علتش را پیدا کن.

- [ ] **Step 5: کد را روی سرور بگذار و تست‌های واحد را همان‌جا اجرا کن**

```bash
ssh root@62.60.193.137 'mkdir -p /opt/fh-test/src'
scp -r bin configs systemd web tests docs root@62.60.193.137:/opt/fh-test/src/
ssh root@62.60.193.137 'cd /opt/fh-test/src && sh tests/run.sh'
```

انتظار: همه‌ی گروه‌ها پاس. سرور `python3` واقعی (۳.۱۲.۳) و `node` ممکن است
نداشته باشد — اگر `node` نبود، گروه web از قلم می‌افتد؛ همان‌ها را روی
ویندوز اجرا کن و اینجا فقط cli و api را بسنج.

سپس سنجش زنده.

- [ ] **Step 6: فایل محیط را بساز و نمونه‌ی جدا را نصب کن**

اول فایل محیطی که `tests/e2e/README.md` توصیف می‌کند:

```bash
ssh root@62.60.193.137 'cat > /opt/fh-test/env.sh <<EOF
export FARSHUB_CONF_DIR=/opt/fh-test/conf
export FARSHUB_LIBEXEC=/opt/fh-test/libexec
export FARSHUB_STATE_DIR=/opt/fh-test/state
export FARSHUB_LOG_DIR=/opt/fh-test/log
export FARSHUB_BIN_DIR=/opt/fh-test/bin
export FARSHUB_UNIT_PREFIX=farshub-test
export FARSHUB_SITE_NAME=farshub-test
export FARSHUB_HTPASSWD=/etc/nginx/farshub-test.htpasswd
export FH=/opt/fh-test/src/bin/farshub
EOF'
```

بسنج که همه‌ی هشت متغیر نشسته‌اند — یکی جاافتاده یعنی آن مسیر سراغ نمونه‌ی
زنده می‌رود:

```bash
ssh root@62.60.193.137 '. /opt/fh-test/env.sh && sh "$FH" paths server'
```

انتظار: هر خط زیر `/opt/fh-test`، و `unit=farshub-test-server.service`. اگر
حتی یک خط `/etc/farshub` یا `farshub-server.service` داشت، **جلوتر نرو**.

بعد نصب:

```bash
ssh root@62.60.193.137 '. /opt/fh-test/env.sh && sh "$FH" install server'
```

بعد بسنج که یونیت تازه ساخته شد و **زنده دست‌نخورده است**:

```bash
ssh root@62.60.193.137 'systemctl cat farshub-test-server.service | head -20; \
  systemctl show -p MainPID --value farshub-server'
```

انتظار: `Environment=FARSHUB_CONF_DIR=/opt/fh-test/conf` در drop-in، و PID
زنده همان مقدار گام ۴.

- [ ] **Step 7: کانفیگ تست را بنویس و روی پورت‌های تست ببر بالا**

```bash
ssh root@62.60.193.137 '. /opt/fh-test/env.sh && \
  printf "bind_addr=0.0.0.0:3990\nweb_port=2062\ntransport=tcpmux\ntoken=%s\nports+=19443\n" "$(openssl rand -hex 32)" \
  | sh "$FH" apply-config server'
```

انتظار: `changed` برای هر پنج کلید. بعد:

```bash
ssh root@62.60.193.137 '. /opt/fh-test/env.sh && sh "$FH" start server && sh "$FH" status server'
ssh root@62.60.193.137 'ss -ltn | grep -E ":(3990|2062)"'
```

انتظار: تونل تست روی `3990` و آمار روی `2062`. و بار دیگر سنجش زنده.

- [ ] **Step 8: پنل و سرویس API تست را بالا بیاور**

```bash
ssh root@62.60.193.137 '. /opt/fh-test/env.sh && \
  sh "$FH" panel-up server --port 8099 --password "TestOnly1405" && \
  sh "$FH" api-up --port 2063'
```

انتظار: `nginx -t` پاس، سایت `farshub-test` روی `8099`، سرویس
`farshub-test-api.service` روی `127.0.0.1:2063` (نام از `UNIT_PREFIX` می‌آید —
تصحیح ۴). بسنج که سرویس API **زنده** هم دست‌نخورده مانده و نام‌ها قاطی نشده:

```bash
ssh root@62.60.193.137 'systemctl is-active farshub-test-api; ls -1 /etc/sudoers.d/ | grep api'
```

انتظار: `active`، و در sudoers فقط `farshub-test-api` (اگر نمونه‌ی زنده هنوز
سرویس API ندارد). **بسنج که سایت زنده دست نخورده:**

```bash
ssh root@62.60.193.137 'md5sum /etc/nginx/sites-available/farshub-panel'
```

باید با مقدار پیش از این تسک یکی باشد.

- [ ] **Step 9: هشت اندپوینت را از خود سرور بسنج**

```bash
ssh root@62.60.193.137 'curl -s -u farshub:TestOnly1405 http://127.0.0.1:8099/api/state | python3 -m json.tool'
```

بعد به ترتیب:
1. `GET /api/config?side=server` → توکن `********`، `web_port` عدد ۲۰۶۲.
2. `GET /api/preflight?side=server` → بدون خطای `pf.tokenDefault`.
3. `PUT /api/config` با `{"side":"server","values":{"log_level":"info"}}` و هدر `Origin: http://127.0.0.1:8099` → `restartNeeded: true`.
4. همان `PUT` **بدون** هدر `Origin` → `403` با `error: origin`.
5. همان `PUT` با `Origin: http://evil.example` → `403`.
6. دو `PUT` پشت‌سرهم → دومی `429` با `error: rate_limit`.
7. `POST /api/service` با `{"side":"server","action":"reboot"}` → `400`.
8. `GET /api/logs?side=server&n=-f` → `200` با حداکثر ۱۰۰ خط (نه اجرای `-f`).
9. `POST /api/token` → توکن ۶۴ نویسه‌ای.

هر کدام باید همان چیزی بدهد که تست‌های تسک ۳ ادعا می‌کنند. **این گام مهم‌ترین
گام تسک است** چون تست‌های واحد `run_cli` را جعل می‌کنند و اینجا اولین بار
است که sudoers و systemd و nginx واقعی در مسیر هستند.

اگر یکی رد شد، پیش از ادامه علتش را پیدا کن. مشکوک‌های همیشگی: sudoers ردیف
جاافتاده (`sudo -n` با `a password is required` برمی‌گردد ولی خطا در `detail`
فارسی نیست)، و `Host` که nginx فرستاده (`$host` جای `$http_host` → هر نوشتنی
`403` می‌شود).

- [ ] **Step 10: در مرورگر از راه تونل SSH بسنج**

```bash
ssh -L 8099:127.0.0.1:8099 root@62.60.193.137
```

بعد در مرورگر `http://127.0.0.1:8099/` را باز کن، رمز `farshub`/`TestOnly1405`
بده، و همان ده سنجش تسک ۷ گام ۶ را روی داده‌ی واقعی تکرار کن. مهم‌ترین‌ها:
ذخیره‌ی یک فیلد، آمدن نوار ری‌استارت، تأیید دیالوگ، و اینکه بعد از ری‌استارت
`ss -ltn` نشان بدهد تونل تست دوباره روی `3990` است و **تونل زنده روی `3080`
یک لحظه هم نرفته**.

- [ ] **Step 11: ویزارد را روی نمونه‌ی خام سوم بسنج**

نمونه‌ی تست حالا نصب‌شده است، پس ویزارد دیده نمی‌شود. یک نمونه‌ی سوم با
پیشوند دیگر بساز که هیچ کانفیگی ندارد:

```bash
ssh root@62.60.193.137 'cat > /opt/fh-w/env.sh <<EOF
export FARSHUB_CONF_DIR=/opt/fh-w/conf
export FARSHUB_LIBEXEC=/opt/fh-w/libexec
export FARSHUB_STATE_DIR=/opt/fh-w/state
export FARSHUB_LOG_DIR=/opt/fh-w/log
export FARSHUB_BIN_DIR=/opt/fh-w/bin
export FARSHUB_UNIT_PREFIX=farshub-w
export FARSHUB_SITE_NAME=farshub-w
export FARSHUB_HTPASSWD=/etc/nginx/farshub-w.htpasswd
export FH=/opt/fh-test/src/bin/farshub
EOF'
ssh root@62.60.193.137 'mkdir -p /opt/fh-w && . /opt/fh-w/env.sh && \
  sh "$FH" panel-up --port 8100 --password "TestOnly1405" && \
  sh "$FH" api-up --port 2064'
```

`panel-up` بدون سمت نصب‌شده باید کار کند (تصحیح شماره‌ی ۳ در بالای این سند).
بعد از تونل SSH روی `8100` ویزارد را کامل کن: نقش `client`، نشانی
`127.0.0.1:3990` (همان تونل تست)، توکن تولیدی. بعد از نصب، سرویس را از کارت
سرویس شروع کن و بسنج که در لاگ **سرور تست** اتصال کلاینت دیده می‌شود:

```bash
ssh root@62.60.193.137 '. /opt/fh-test/env.sh && sh "$FH" logs server -n 30' | grep -i 'connect'
```

این تنها گامی است که **کل چرخه** را می‌سنجد: سرور خام → ویزارد → تونل زنده.

- [ ] **Step 12: نمونه‌های تست را کامل جمع کن**

به ترتیب معکوس، هر نمونه با فایل محیط خودش. اول نمونه‌ی ویزارد (کلاینت):

```bash
ssh root@62.60.193.137 '. /opt/fh-w/env.sh && \
  sh "$FH" api-down; sh "$FH" panel-down; \
  sh "$FH" stop client; sh "$FH" uninstall client'
```

بعد نمونه‌ی تست (سرور):

```bash
ssh root@62.60.193.137 '. /opt/fh-test/env.sh && \
  sh "$FH" api-down; sh "$FH" panel-down; \
  sh "$FH" stop server; sh "$FH" uninstall server'
```

اگر `uninstall` تأیید تعاملی می‌خواهد، پرچم بی‌سؤالش را بده یا `yes |` جلویش
بگذار. بعد باقی‌مانده‌ها:

```bash
ssh root@62.60.193.137 'rm -rf /opt/fh-test /opt/fh-w /etc/nginx/farshub-test.htpasswd /etc/nginx/farshub-w.htpasswd'
ssh root@62.60.193.137 'systemctl daemon-reload; nginx -t && systemctl reload nginx'
```

بعد سنجش پایانی — این فهرست باید **دقیقاً** همان چیزی باشد که در گام ۴ ثبت شد:

```bash
ssh root@62.60.193.137 'systemctl list-units "farshub*" --all --no-legend; \
  ls /etc/nginx/sites-enabled/; \
  systemctl show -p MainPID --value farshub-server; \
  systemctl is-active farshub-server nginx; \
  ss -ltn | grep -E ":(3080|2060|8088|3990|2062|2063|8099|8100|2064)"'
```

انتظار: فقط `farshub-server.service`، فقط سایت `farshub-panel`، همان PID گام
۴، هر دو `active`، و از پورت‌ها فقط `3080`/`2060`/`8088`.

- [ ] **Step 13: commit**

```bash
git add docs/PANEL.md docs/CLI.md README.md tests/e2e/README.md
git commit -m "مستندات: مسیر پنل برای کانفیگ تونل و دفترچه‌ی آزمون سرتاسری"
```

---

## بازبینی نهایی

پیش از تحویل، این سه را روی کد نوشته‌شده بسنج:

- [ ] `sh tests/run.sh` روی ویندوز (Git Bash) و روی سرور، هر دو سبز
- [ ] `git diff --stat bin/farshub-core` خالی، و `md5sum bin/farshub-core` برابر `2f86ffb6ab33de43abfc606e12a8d972`
- [ ] هیچ کلید i18n جامانده: در کنسول مرورگر روی هر دو تب و هر دو زبان،
      `[...document.querySelectorAll('*')].filter(n => n.children.length === 0 && /^(tab|svc|save|cfg|err|api|pf|wz)\.[a-zA-Z]/.test(n.textContent.trim())).length` باید `0` بدهد

## پوشش اسپک

| بخش اسپک | تسک |
|---|---|
| معماری سه‌لایه (nginx / API / CLI) | ۳، ۴ |
| هشت اندپوینت | ۳ (سرور)، ۵ (کلاینت) |
| `apply-config` با اعتبارسنجی | ۲ |
| `api-up` / `api-down` / `setup` | ۴ |
| دو تب و کارت سرویس | ۶ |
| چهار کارت فرم و preflight | ۷ |
| ویزارد سه‌گامی | ۸ |
| جدول کاهش تهدید (Origin، rate limit، sudoers بسته، ۱۲۷.۰.۰.۱) | ۳، ۴، سنجش در ۹ گام ۹ |
| چیدمان نمونه‌ی جدا | ۱ (متغیرها)، ۹ (اجرا) |
| مستندات | ۹ |
