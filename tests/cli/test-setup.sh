#!/bin/sh
# «setup» ویزارد تعاملی است: پاسخ‌ها خط‌به‌خط از stdin خوانده می‌شوند، پرسش‌ها
# و هشدارها به stderr می‌روند و خلاصه‌ی نهایی با «Setup complete.» به stdout —
# تا اجرای pipe شده هم اسکریپت‌پذیر باشد و هم قابل تست. این فایل شکلِ pinned
# همان رابط را به‌صورت اجرایی ثبت می‌کند و تا پیاده‌سازی شدنِ setup شکست
# می‌خورد (TDD): امروز setup به موتور پاس‌ترو می‌شود و با موتورِ استاب،
# خروجی خالی و rc صفر می‌دهد؛ پس هر چیزی که درباره‌ی متن خروجی یا کدهای ۱
# و ۲ سنجیده می‌شود قرمز است. getent با استاب شبیه‌سازی می‌شود (IPها از
# STUB_IPS می‌آیند) و stdin همیشه با خط جدید پایانی ساخته می‌شود تا read
# آخر به EOF نخورد.
set -u
. "$(dirname -- "$0")/../lib.sh"

stub=$(mktemp -d)
rm_on_exit=''
trap 'rm -rf $rm_on_exit "$stub"' EXIT

# استاب getent — همان الگوی test-check-cdn.sh.
cat >"$stub/getent" <<'EOF'
#!/bin/sh
[ "$1" = hosts ] && [ "$#" -ge 2 ] && printf '%s\n' "$STUB_IPS"
exit 0
EOF
chmod +x "$stub/getent"

nl='
'
inp() {   # هر آرگومان = یک خط پاسخ؛ حاصل در ANS، همیشه با خط جدید پایانی
  ANS=''
  for _a in "$@"; do ANS="$ANS$_a$nl"; done
}

# fixture تازه با موتورِ استاب در libexec — هم برای پاس‌تروی امروز، هم برای
# نصبی که setup بعداً اجرایش می‌کند.
newf() {
  _f=$(fixture)
  printf '#!/bin/sh\n' >"$_f/libexec/farshub-core"
  chmod +x "$_f/libexec/farshub-core" 2>/dev/null || true
  rm_on_exit="$rm_on_exit $_f"
  printf '%s\n' "$_f"
}

# اجرای setup: stdin + انزوای محیطی + stderr جدا — الگوی prun در test-peers.
srun() {                                   # $1=fixture؛ $2=stdin؛ بقیه → farshub
  _d=$1; _in=$2; shift 2
  : >"$stub/stderr.txt"
  OUT=$(printf '%s' "$_in" | env PATH="$stub:$PATH" STUB_IPS="${STUB_IPS:-}" \
    FARSHUB_CONF_DIR="$_d/conf" FARSHUB_LIBEXEC="$_d/libexec" \
    FARSHUB_BIN_DIR="$_d/bin" FARSHUB_UNIT_DIR="$_d/units" \
    FARSHUB_LOG_DIR="$_d/log" FARSHUB_STATE_DIR="$_d/state" \
    FARSHUB_UNIT_PREFIX=farshub-test FARSHUB_SITE_NAME=farshub-test \
    sh "$FARSHUB" "$@" 2>"$stub/stderr.txt")
  RC=$?
  ERR=$(cat "$stub/stderr.txt" 2>/dev/null)
  return 0
}

# حالت‌های «نیست» که lib.sh ندارد.
assert_no_file() {                         # $1=برچسب  $2=مسیر
  if [ -e "$2" ]; then bad "$1" "نباید می‌بود: $2"; else ok "$1"; fi
}
assert_dir_empty() {                       # $1=برچسب  $2=مسیر
  if [ -n "$(ls -A "$2" 2>/dev/null)" ]; then
    bad "$1" "خالی نبود: $(ls -A "$2" 2>/dev/null)"
  else
    ok "$1"
  fi
}
assert_no_toml() {                         # $1=برچسب  $2=fixture
  if ls "$2"/conf/*.toml >/dev/null 2>&1; then
    bad "$1" "کانفیگ نوشته شد: $(ls "$2"/conf/*.toml 2>/dev/null)"
  else
    ok "$1"
  fi
}
assert_file_eq() {                         # $1=برچسب  $2=انتظار  $3=واقعی
  if cmp -s "$2" "$3"; then ok "$1"
  else bad "$1" "محتوا فرق دارد:
--- انتظار
$(cat "$2" 2>/dev/null)
--- واقعی
$(cat "$3" 2>/dev/null)"
  fi
}
assert_match() {                           # $1=برچسب  $2=مقدار  $3=الگوی grep -E
  if printf '%s' "$2" | grep -Eq "$3"; then ok "$1"
  else bad "$1" "«$2» با /$3/ نمی‌خواند"; fi
}

# --- ۱) آرگومان سمت --------------------------------------------------------
STUB_IPS=''
d1=$(newf)
srun "$d1" '' setup bogus
assert_rc 'سمت bogus: rc 2' 2
assert_contains 'سمت bogus: پیام invalid side' "$ERR" \
  "farshub: invalid side: 'bogus' (server or client)"

inp '' '' '' '' '' ''
srun "$d1" "$ANS" setup s
assert_rc 'setup s: rc صفر' 0
assert_contains 'setup s: مثل server رفتار می‌کند' "$OUT" 'Side:           server'
assert_contains 'setup s: تا Setup complete می‌رسد' "$OUT" 'Setup complete.'

inp 87.107.81.96:2083 '' '' '' ''
srun "$d1" "$ANS" setup c
assert_rc 'setup c: rc صفر' 0
assert_contains 'setup c: مثل client رفتار می‌کند' "$OUT" 'Side:           client'
assert_contains 'setup c: تا Setup complete می‌رسد' "$OUT" 'Setup complete.'

# --- ۲) سؤال سمت -----------------------------------------------------------
STUB_IPS=''
d2=$(newf)
inp server '' '' '' '' '' ''
srun "$d2" "$ANS" setup
assert_contains 'بدون سمت: پرسش سمت در stderr' "$ERR" \
  'Side - server listens, client dials [server/client]: '
assert_contains 'بدون سمت: پس از پاسخ سراغ سؤال بعد می‌رود' "$ERR" \
  'Tunnel listen address [0.0.0.0:2083]: '
assert_rc 'بدون سمت: rc صفر' 0
assert_contains 'بدون سمت: خلاصه سمت سرور' "$OUT" 'Side:           server'

d2b=$(newf)
inp x x x
srun "$d2b" "$ANS" setup
assert_rc 'سمت نامعتبر ×۳: rc 1' 1
assert_contains 'سمت نامعتبر ×۳: پیام too many invalid answers' "$ERR" \
  'farshub: setup aborted - too many invalid answers'
assert_no_toml 'سمت نامعتبر ×۳: کانفیگی نوشته نشد' "$d2b"
assert_dir_empty 'سمت نامعتبر ×۳: units خالی ماند' "$d2b/units"

# حتی وقتی فقط یک سمت نصب است، setup حدس نمی‌زند؛ همیشه می‌پرسد.
d2c=$(newf)
printf '# installed side\n' >"$d2c/conf/server.toml"
inp client 87.107.81.96:2083 '' '' '' ''
srun "$d2c" "$ANS" setup
assert_contains 'یک سمت نصب است: سؤال سمت پرسیده می‌شود' "$ERR" \
  'Side - server listens, client dials [server/client]: '
assert_missing 'یک سمت نصب است: حدس زده نشد' "$ERR" 'Overwrite?'
assert_rc 'یک سمت نصب است: rc صفر' 0

# --- ۳) EOF -----------------------------------------------------------------
STUB_IPS=''
d3=$(newf)
srun "$d3" '' setup server
assert_rc 'EOF: rc 1' 1
assert_contains 'EOF: پیام no input' "$ERR" 'farshub: setup aborted - no input'
assert_no_toml 'EOF: کانفیگی نوشته نشد' "$d3"
assert_dir_empty 'EOF: units خالی ماند' "$d3/units"
assert_no_file 'EOF: state/web ساخته نشد' "$d3/state/web"

# --- ۴) سرور با پیش‌فرض‌ها + استثنای چاپ کامل توکن ----------------------------
STUB_IPS=''
s4=$(newf)
inp '' '' '' '' '' ''
srun "$s4" "$ANS" setup server
assert_rc 'پیش‌فرض سرور: rc صفر' 0
tok=$(printf '%s' "$OUT" | sed -n 's/^Token:[[:space:]]*//p')
assert_contains 'پیش‌فرض سرور: خط Side' "$OUT" 'Side:           server'
assert_contains 'پیش‌فرض سرور: خط Listen' "$OUT" 'Listen:         0.0.0.0:2083'
assert_contains 'پیش‌فرض سرور: خط Transport' "$OUT" 'Transport:      tcpmux'
assert_contains 'پیش‌فرض سرور: خط Token' "$OUT" "Token:          $tok"
assert_match 'پیش‌فرض سرور: توکن ۶۴ نویسه‌ی hex' "$tok" '^[0-9a-f]{64}$'
assert_contains 'پیش‌فرض سرور: خط Ports با -' "$OUT" 'Ports:          -'
assert_contains 'پیش‌فرض سرور: هشدار بدون نگاشت بلافاصله بعد از Ports' "$OUT" \
  "Ports:          -${nl}Warning: no port mappings - the tunnel will forward no user ports."
assert_contains 'پیش‌فرض سرور: خط Web port' "$OUT" 'Web port:       0'
assert_contains 'پیش‌فرض سرور: Setup complete.' "$OUT" 'Setup complete.'
assert_contains 'پیش‌فرض سرور: خط Config' "$OUT" "Config: $s4/conf/server.toml"
assert_contains 'پیش‌فرض سرور: دستور start در Next' "$OUT" '  sudo farshub start'
assert_contains 'پیش‌فرض سرور: دستور check در Next' "$OUT" '  sudo farshub check'
assert_contains 'پیش‌فرض سرور: دستور panel-up در Next' "$OUT" \
  '  sudo farshub panel-up    (optional web panel)'
assert_contains 'پیش‌فرض سرور: پرسش listen در stderr' "$ERR" \
  'Tunnel listen address [0.0.0.0:2083]: '
assert_contains 'پیش‌فرض سرور: پرسش transport در stderr' "$ERR" 'Transport [tcpmux]: '
assert_contains 'پیش‌فرض سرور: پرسش توکن در stderr' "$ERR" \
  'Auth token - [g]enerate or [e]nter [g]: '
assert_contains 'پیش‌فرض سرور: پرسش پورت در stderr' "$ERR" \
  'Port mapping (local=remote[:dest]) - empty to finish: '
assert_contains 'پیش‌فرض سرور: پرسش وب در stderr' "$ERR" 'Web/panel port [0]: '
assert_contains 'پیش‌فرض سرور: پرسش تأیید در stderr' "$ERR" \
  'Write config and install? [Y/n]: '
assert_missing 'پیش‌فرض سرور: خلاصه در stderr نیست' "$ERR" 'Setup complete.'
assert_missing 'پیش‌فرض سرور: خط Side: در stderr نیست' "$ERR" 'Side:'
assert_missing 'پیش‌فرض سرور: پرسش تأیید در stdout نیست' "$OUT" \
  'Write config and install?'
body=$(cat "$s4/conf/server.toml" 2>/dev/null)
assert_contains 'پیش‌فرض سرور: توکنِ چاپ‌شده عین توکن فایل است' "$body" \
  "token = \"$tok\""
assert_missing 'پیش‌فرض سرور: کلید heartbeat نیست' "$body" 'heartbeat'
assert_missing 'پیش‌فرض سرور: کلید sniffer نیست' "$body" 'sniffer'
assert_missing 'پیش‌فرض سرور: کلید log_level نیست' "$body" 'log_level'
assert_missing 'پیش‌فرض سرور: کلید keepalive نیست' "$body" 'keepalive'
cat >"$stub/exp.toml" <<EOF
# FarsHub Tunnel - server config - written by 'farshub setup'
# full option list: farshub config / docs/CLI.md
# keys are compiled into the engine - change values only

[server]
bind_addr = "0.0.0.0:2083"
transport = "tcpmux"
token = "$tok"
ports = []
web_port = 0
EOF
assert_file_eq 'پیش‌فرض سرور: فایل کانفیگ بایت‌به‌بایت درست' \
  "$stub/exp.toml" "$s4/conf/server.toml"
assert_file 'پیش‌فرض سرور: یونیت systemd نصب شد' \
  "$s4/units/farshub-test-server.service"
assert_file 'پیش‌فرض سرور: پنل وب نصب شد' "$s4/state/web/index.html"
assert_file 'پیش‌فرض سرور: payload نصب شد' "$s4/state/payload/configs/server.toml"

# --- ۵) سرور با مدخل‌های پورت ------------------------------------------------
STUB_IPS=''
s5=$(newf)
inp 0.0.0.0:2083 '' '' 443 8443=443 42099=35.207.200.69:443 '' 8080 y
srun "$s5" "$ANS" setup server
assert_rc 'ورودی‌دار سرور: rc صفر' 0
tok5=$(printf '%s' "$OUT" | sed -n 's/^Token:[[:space:]]*//p')
assert_contains 'ورودی‌دار سرور: خط Ports با سه مدخل' "$OUT" \
  'Ports:          443, 8443=443, 42099=35.207.200.69:443'
assert_contains 'ورودی‌دار سرور: خط Web port' "$OUT" 'Web port:       8080'
cat >"$stub/exp.toml" <<EOF
# FarsHub Tunnel - server config - written by 'farshub setup'
# full option list: farshub config / docs/CLI.md
# keys are compiled into the engine - change values only

[server]
bind_addr = "0.0.0.0:2083"
transport = "tcpmux"
token = "$tok5"
ports = [
    "443",
    "8443=443",
    "42099=35.207.200.69:443",
]
web_port = 8080
EOF
assert_file_eq 'ورودی‌دار سرور: فایل با بلوک سه‌ردیفی ports' \
  "$stub/exp.toml" "$s5/conf/server.toml"

# --- ۶) تاب‌خوردن حلقه‌ی ports -------------------------------------------------
STUB_IPS=''
s6=$(newf)
inp '' '' '' 99999 443 '' '' ''
srun "$s6" "$ANS" setup server
assert_rc 'حلقه‌ی ports: rc صفر با ورودی نامعتبر' 0
assert_contains 'حلقه‌ی ports: پیام invalid ports entry' "$ERR" 'invalid ports entry'
assert_contains 'حلقه‌ی ports: فقط پورت معتبر ماند' "$OUT" 'Ports:          443'
assert_contains 'حلقه‌ی ports: بلوک تک‌ردیفی در فایل' \
  "$(cat "$s6/conf/server.toml" 2>/dev/null)" \
  "ports = [${nl}    \"443\",${nl}]"

# --- ۷) نامعتبر و بعد معتبر ---------------------------------------------------
STUB_IPS=''
s7a=$(newf)
inp abc 0.0.0.0:2083 '' '' '' '' ''
srun "$s7a" "$ANS" setup server
assert_rc 'listen نامعتبر: rc صفر پس از اصلاح' 0
assert_contains 'listen نامعتبر: پیام must be host:port' "$ERR" 'must be host:port'
assert_contains 'listen نامعتبر: مقدار اصلاح‌شده در خلاصه' "$OUT" \
  'Listen:         0.0.0.0:2083'

s7b=$(newf)
inp '' quic ws '' '' '' ''
srun "$s7b" "$ANS" setup server
assert_rc 'transport نامعتبر: rc صفر پس از اصلاح' 0
assert_contains 'transport نامعتبر: پیام invalid transport' "$ERR" 'invalid transport'
assert_contains 'transport نامعتبر: مقدار اصلاح‌شده در خلاصه' "$OUT" \
  'Transport:      ws'

s7c=$(newf)
inp '' '' e short 0123456789abcdef0123456789abcdef '' '' ''
srun "$s7c" "$ANS" setup server
assert_rc 'توکن دستی: rc صفر پس از اصلاح' 0
assert_contains 'توکن دستی: پرسش Token: در stderr' "$ERR" 'Token: '
assert_contains 'توکن دستی: پیام ۳۲ تا ۲۵۶ نویسه' "$ERR" '32-256 characters'
assert_contains 'توکن دستی: توکن واردشده در فایل' \
  "$(cat "$s7c/conf/server.toml" 2>/dev/null)" \
  'token = "0123456789abcdef0123456789abcdef"'

s7d=$(newf)
inp '' '' '' '' 99999 0 ''
srun "$s7d" "$ANS" setup server
assert_rc 'وب نامعتبر: rc صفر پس از اصلاح' 0
assert_contains 'وب نامعتبر: پیام بین ۰ و ۶۵۵۳۵' "$ERR" 'between 0 and 65535'
assert_contains 'وب نامعتبر: مقدار اصلاح‌شده در خلاصه' "$OUT" 'Web port:       0'

# --- ۸) سه خطای پیاپی ----------------------------------------------------------
STUB_IPS=''
s8a=$(newf)
inp abc abc abc
srun "$s8a" "$ANS" setup server
assert_rc 'سه خطا listen: rc 1' 1
assert_contains 'سه خطا listen: پیام too many invalid answers' "$ERR" \
  'farshub: setup aborted - too many invalid answers'
assert_no_toml 'سه خطا listen: کانفیگی نوشته نشد' "$s8a"
assert_dir_empty 'سه خطا listen: units خالی ماند' "$s8a/units"

s8b=$(newf)
inp '' quic quic quic
srun "$s8b" "$ANS" setup server
assert_rc 'سه خطا transport: rc 1' 1
assert_contains 'سه خطا transport: پیام too many invalid answers' "$ERR" \
  'farshub: setup aborted - too many invalid answers'
assert_no_toml 'سه خطا transport: کانفیگی نوشته نشد' "$s8b"
assert_dir_empty 'سه خطا transport: units خالی ماند' "$s8b/units"

s8c=$(newf)
inp '' '' e short short short
srun "$s8c" "$ANS" setup server
assert_rc 'سه خطا توکن: rc 1' 1
assert_contains 'سه خطا توکن: پیام too many invalid answers' "$ERR" \
  'farshub: setup aborted - too many invalid answers'
assert_no_toml 'سه خطا توکن: کانفیگی نوشته نشد' "$s8c"
assert_dir_empty 'سه خطا توکن: units خالی ماند' "$s8c/units"

s8d=$(newf)
inp '' '' ''
srun "$s8d" "$ANS" setup client
assert_rc 'سه خطا نشانی سرور: rc 1' 1
assert_contains 'سه خطا نشانی سرور: پیام too many invalid answers' "$ERR" \
  'farshub: setup aborted - too many invalid answers'
assert_no_toml 'سه خطا نشانی سرور: کانفیگی نوشته نشد' "$s8d"
assert_dir_empty 'سه خطا نشانی سرور: units خالی ماند' "$s8d/units"

# --- ۹) کانفیگ موجود -------------------------------------------------------------
STUB_IPS=''
o9=$(newf)
cat >"$o9/conf/server.toml" <<'EOF'
# old config
bind_addr = "1.2.3.4:9"
EOF
cp "$o9/conf/server.toml" "$stub/old9.toml"

inp ''
srun "$o9" "$ANS" setup server
assert_contains 'کانفیگ موجود: پرسش Overwrite در stderr' "$ERR" \
  "Config file $o9/conf/server.toml already exists. Overwrite? [y/N]: "
assert_rc 'کانفیگ موجود (پاسخ خالی): rc 1' 1
assert_contains 'کانفیگ موجود (پاسخ خالی): پیام existing config kept' "$ERR" \
  'farshub: setup aborted - existing config kept'
assert_file_eq 'کانفیگ موجود (پاسخ خالی): فایل دست‌نخورده' \
  "$stub/old9.toml" "$o9/conf/server.toml"

inp n
srun "$o9" "$ANS" setup server
assert_rc 'کانفیگ موجود (n): rc 1' 1
assert_contains 'کانفیگ موجود (n): پیام existing config kept' "$ERR" \
  'farshub: setup aborted - existing config kept'
assert_file_eq 'کانفیگ موجود (n): فایل دست‌نخورده' \
  "$stub/old9.toml" "$o9/conf/server.toml"

inp y '' '' '' '' '' ''
srun "$o9" "$ANS" setup server
assert_rc 'کانفیگ موجود (y): rc صفر' 0
tok9=$(printf '%s' "$OUT" | sed -n 's/^Token:[[:space:]]*//p')
assert_file_eq 'کانفیگ موجود (y): پشتیبان .bak محتوای قدیم' \
  "$stub/old9.toml" "$o9/conf/server.toml.bak"
cat >"$stub/exp.toml" <<EOF
# FarsHub Tunnel - server config - written by 'farshub setup'
# full option list: farshub config / docs/CLI.md
# keys are compiled into the engine - change values only

[server]
bind_addr = "0.0.0.0:2083"
transport = "tcpmux"
token = "$tok9"
ports = []
web_port = 0
EOF
assert_file_eq 'کانفیگ موجود (y): فایل جدید فرمت ویزارد' \
  "$stub/exp.toml" "$o9/conf/server.toml"

# پاسخ ناشناخته به پرسش بله/خیر: سه بار پیاپی = سقط؛ کانفیگ قدیمی می‌ماند.
o9b=$(newf)
cat >"$o9b/conf/server.toml" <<'EOF'
# old config
EOF
inp maybe maybe maybe
srun "$o9b" "$ANS" setup server
assert_rc 'پاسخ ناشناخته ×۳: rc 1' 1
assert_contains 'پاسخ ناشناخته ×۳: پیام too many invalid answers' "$ERR" \
  'farshub: setup aborted - too many invalid answers'
assert_contains 'پاسخ ناشناخته ×۳: کانفیگ قدیمی ماند' \
  "$(cat "$o9b/conf/server.toml" 2>/dev/null)" '# old config'

# --- ۱۰) رد تأیید نهایی ------------------------------------------------------------
STUB_IPS=''
d10=$(newf)
inp '' '' '' '' '' n
srun "$d10" "$ANS" setup server
assert_rc 'رد تأیید نهایی: rc 1' 1
assert_contains 'رد تأیید نهایی: پیام nothing written' "$ERR" \
  'farshub: setup aborted - nothing written'
assert_no_toml 'رد تأیید نهایی: کانفیگی نوشته نشد' "$d10"
assert_dir_empty 'رد تأیید نهایی: units خالی ماند' "$d10/units"
assert_no_file 'رد تأیید نهایی: state/web ساخته نشد' "$d10/state/web"

# --- ۱۱) کلاینت با IP مستقیم --------------------------------------------------------
STUB_IPS=87.107.81.96
c11=$(newf)
inp 87.107.81.96:2083 '' '' '' ''
srun "$c11" "$ANS" setup client
assert_rc 'کلاینت IP: rc صفر' 0
tokc=$(printf '%s' "$OUT" | sed -n 's/^Token:[[:space:]]*//p')
assert_contains 'کلاینت IP: خط Side' "$OUT" 'Side:           client'
assert_contains 'کلاینت IP: خط Server' "$OUT" 'Server:         87.107.81.96:2083'
assert_contains 'کلاینت IP: خط Resolved' "$OUT" 'Resolved:       87.107.81.96'
assert_contains 'کلاینت IP: خط Transport' "$OUT" 'Transport:      tcpmux'
assert_contains 'کلاینت IP: خط Web port' "$OUT" 'Web port:       0'
assert_contains 'کلاینت IP: Setup complete.' "$OUT" 'Setup complete.'
assert_contains 'کلاینت IP: یادداشت توکن دو طرف' "$OUT" \
  'The token must match the server side exactly.'
cbody=$(cat "$c11/conf/client.toml" 2>/dev/null)
assert_contains 'کلاینت IP: سرصفحه‌ی [client]' "$cbody" '[client]'
assert_contains 'کلاینت IP: remote_addr در فایل' "$cbody" \
  'remote_addr = "87.107.81.96:2083"'
assert_missing 'کلاینت IP: کلید ports نیست' "$cbody" 'ports ='
cat >"$stub/exp.toml" <<EOF
# FarsHub Tunnel - client config - written by 'farshub setup'
# full option list: farshub config / docs/CLI.md
# keys are compiled into the engine - change values only

[client]
remote_addr = "87.107.81.96:2083"
transport = "tcpmux"
token = "$tokc"
web_port = 0
EOF
assert_file_eq 'کلاینت IP: فایل بایت‌به‌بایت درست' \
  "$stub/exp.toml" "$c11/conf/client.toml"

# --- ۱۲) دامنه با DNS ----------------------------------------------------------------
STUB_IPS=87.107.81.96
c12=$(newf)
inp tunnel.example.com:2083 '' '' '' ''
srun "$c12" "$ANS" setup client
assert_rc 'دامنه با DNS: rc صفر' 0
assert_contains 'دامنه با DNS: خط Server' "$OUT" 'Server:         tunnel.example.com:2083'
assert_contains 'دامنه با DNS: IP حل‌شده در Resolved' "$OUT" 'Resolved:       87.107.81.96'
assert_missing 'دامنه با DNS: هشداری نیست' "$ERR" 'Warning:'

# --- ۱۳) دامنه بدون DNS ----------------------------------------------------------------
STUB_IPS=''
c13=$(newf)
inp tunnel.example.com:2083 '' '' '' ''
srun "$c13" "$ANS" setup client
assert_rc 'دامنه بدون DNS: rc صفر' 0
assert_contains 'دامنه بدون DNS: هشدار could not resolve' "$ERR" \
  'Warning: could not resolve tunnel.example.com - configuring as entered.'
assert_contains 'دامنه بدون DNS: Resolved خط تیره' "$OUT" 'Resolved:       -'
assert_contains 'دامنه بدون DNS: تا پایان می‌رسد' "$OUT" 'Setup complete.'

# --- ۱۴) دامنه‌ی پشت کلادفلر + tcpmux -----------------------------------------------------
STUB_IPS=104.21.46.216
c14=$(newf)
inp tunnel.example.com:2083 '' ''
srun "$c14" "$ANS" setup client
assert_contains 'کلادفلر tcpmux: هشدار Warning' "$ERR" 'Warning:'
assert_contains 'کلادفلر tcpmux: ذکر Cloudflare' "$ERR" 'Cloudflare'
assert_contains 'کلادفلر tcpmux: پرسش Continue anyway' "$ERR" 'Continue anyway? [y/N]: '
assert_rc 'کلادفلر tcpmux (رد): rc 1' 1
assert_contains 'کلادفلر tcpmux (رد): پیام سقط ws*' "$ERR" \
  'farshub: setup aborted - Cloudflare-proxied address requires a ws* transport'
assert_no_toml 'کلادفلر tcpmux (رد): چیزی نوشته نشد' "$c14"

inp tunnel.example.com:2083 '' y '' '' ''
srun "$c14" "$ANS" setup client
assert_rc 'کلادفلر tcpmux (ادامه): rc صفر' 0
assert_contains 'کلادفلر tcpmux (ادامه): Setup complete.' "$OUT" 'Setup complete.'
assert_file 'کلادفلر tcpmux (ادامه): کانفیگ client نوشته شد' "$c14/conf/client.toml"

# --- ۱۵) دامنه‌ی پشت کلادفلر + wss --------------------------------------------------------
STUB_IPS=104.21.46.216
c15=$(newf)
inp tunnel.example.com:2083 wss '' '' ''
srun "$c15" "$ANS" setup client
assert_rc 'کلادفلر wss: rc صفر' 0
assert_missing 'کلادفلر wss: هشداری نیست' "$ERR" 'Warning:'
assert_missing 'کلادفلر wss: پرسش Continue نیست' "$ERR" 'Continue anyway?'
assert_contains 'کلادفلر wss: transport درست' "$OUT" 'Transport:      wss'
assert_contains 'کلادفلر wss: Setup complete.' "$OUT" 'Setup complete.'

# --- ۱۶) IP مستقیم کلادفلر ---------------------------------------------------------------
STUB_IPS=''
c16=$(newf)
inp 104.21.46.216:2083 '' n
srun "$c16" "$ANS" setup client
assert_contains 'IP مستقیم کلادفلر: هشدار Warning' "$ERR" 'Warning:'
assert_contains 'IP مستقیم کلادفلر: ذکر Cloudflare' "$ERR" 'Cloudflare'
assert_contains 'IP مستقیم کلادفلر: پرسش Continue anyway' "$ERR" 'Continue anyway? [y/N]: '
assert_rc 'IP مستقیم کلادفلر (n): rc 1' 1
assert_contains 'IP مستقیم کلادفلر (n): پیام سقط ws*' "$ERR" \
  'farshub: setup aborted - Cloudflare-proxied address requires a ws* transport'

# --- ۱۷) راهنما -----------------------------------------------------------------------------
fh help
assert_rc 'راهنما: rc صفر' 0
assert_contains 'راهنما: ردیف setup' "$OUT" 'setup [side]'

summary
