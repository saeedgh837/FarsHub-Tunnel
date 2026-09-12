#!/bin/sh
# تایمر peers با دستورهای داخلی _peers-install/_peers-uninstall ساخته و برچیده
# می‌شود — panel-up/down همین‌ها را صدا می‌زنند، ولی خودشان روی Git Bash سرتاسری
# اجرا نمی‌شوند (/etc/nginx و systemd واقعی می‌خواهند). پس مرز کار همین‌جاست:
# یونیت‌ها، فعال‌سازی تایمر، پرایم peers.json، idempotency و رفتار panel-down.
# systemctl و ss و curl و id با استاب شبیه‌سازی می‌شوند (الگوی test-peers و
# test-check-cdn).
set -u
. "$(dirname -- "$0")/../lib.sh"

[ -n "$PY" ] || { printf '  %s — python لازم دارد\n' "$NAME"; exit 1; }

stub=$(mktemp -d)
rm_on_exit=''
trap 'rm -rf $rm_on_exit "$stub"' EXIT

# استاب ss — همان الگوی test-peers: فقط فراخوانی pinned را می‌پذیرد.
cat >"$stub/ss" <<'EOF'
#!/bin/sh
[ "$1" = -H ] && [ "$2" = -tn ] && [ "$3" = state ] && [ "$4" = established ] || exit 1
cat "$SS_FILE"
EOF

# استاب curl — پاسخ /data و /stats از متغیر محیطی (الگوی test-peers).
cat >"$stub/curl" <<'EOF'
#!/bin/sh
[ "${CURL_RC:-0}" = 0 ] || exit 1
case "$*" in
  *"/data")  printf '%s' "${DATA_RESP:-}" ;;
  *"/stats") printf '%s' "${STATS_RESP:-}" ;;
  *) exit 1 ;;
esac
EOF

# استاب systemctl: هر فراخوانی با آرگومانهای کاملش لاگ می‌شود؛ همیشه موفق.
cat >"$stub/systemctl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$SYSTEMD_LOG"
exit 0
EOF

# استاب id: panel-down به root نیاز دارد؛ برای بقیه‌ی دستورها بی‌اثر است.
cat >"$stub/id" <<'EOF'
#!/bin/sh
[ "${1:-}" = -u ] && printf '0\n'
exit 0
EOF

chmod +x "$stub"/* 2>/dev/null || true
: >"$stub/ss.out"
SYSTEMD_LOG="$stub/systemctl.log"

# اجرای farshub با استابها روی PATH و همان انزوای محیطی envrun. لاگ systemctl
# پیش از هر اجرا پاک می‌شود تا ادعای هر سناریو جدا سنجیده شود.
prun() {                                   # $1=دایرکتوری fixture؛ بقیه → farshub
  _d=$1; shift
  : >"$SYSTEMD_LOG"
  OUT=$(env PATH="$stub:$PATH" SS_FILE="$stub/ss.out" SYSTEMD_LOG="$SYSTEMD_LOG" \
    CURL_RC="${CURL_RC:-0}" DATA_RESP="${DATA_RESP:-}" STATS_RESP="${STATS_RESP:-}" \
    FARSHUB_CONF_DIR="$_d/conf" FARSHUB_LIBEXEC="$_d/libexec" \
    FARSHUB_BIN_DIR="$_d/bin" FARSHUB_UNIT_DIR="$_d/units" \
    FARSHUB_LOG_DIR="$_d/log" FARSHUB_STATE_DIR="$_d/state" \
    FARSHUB_UNIT_PREFIX=farshub-test FARSHUB_SITE_NAME=farshub-test \
    FARSHUB_HTPASSWD="$_d/htpasswd" \
    sh "$FARSHUB" "$@" 2>"$stub/stderr.txt")
  RC=$?
  ERR=$(cat "$stub/stderr.txt" 2>/dev/null)
  return 0
}

# lib.sh بودنِ فایل را می‌سنجد؛ نبودن را هم لازم داریم.
assert_gone() { [ ! -e "$2" ] && ok "$1" || bad "$1" "هنوز هست: $2"; }

# --- نصب: یونیت‌ها، فعال‌سازی تایمر، پرایم -----------------------------------
s=$(fixture server); rm_on_exit="$rm_on_exit $s"
sed -i -e 's/^bind_addr = .*/bind_addr = "0.0.0.0:2083"/' \
       -e 's/^web_port = .*/web_port = 2060/' "$s/conf/server.toml"
cat >"$stub/ss.out" <<'EOF'
ESTAB 0 0 10.0.0.1:2083 31.56.178.224:40198
ESTAB 0 0 10.0.0.1:2083 31.56.178.224:40199
EOF
DATA_RESP='[{"Port":40199,"ReadableUsage":"201.88 MB"}]'

prun "$s" _peers-install server
assert_rc 'نصب: rc صفر' 0
assert_eq 'نصب: stderr خالی' "$ERR" ''
assert_file 'نصب: یونیت سرویس نوشته شد' "$s/units/farshub-test-peers.service"
assert_file 'نصب: یونیت تایمر نوشته شد' "$s/units/farshub-test-peers.timer"
svc=$(cat "$s/units/farshub-test-peers.service")
assert_contains 'یونیت: Type=oneshot' "$svc" 'Type=oneshot'
assert_contains 'یونیت: سمت در Description' "$svc" 'peers JSON (سمت server)'
assert_contains 'یونیت: مسیر کانفیگ در Environment' "$svc" \
  "Environment=FARSHUB_CONF_DIR=$s/conf"
assert_contains 'یونیت: پیشوند در Environment' "$svc" \
  'Environment=FARSHUB_UNIT_PREFIX=farshub-test'
assert_contains 'یونیت: ExecStart با بازنویسی اتمیک' "$svc" \
  "ExecStart=/bin/sh -c '$s/bin/farshub peers server > $s/state/web/peers.json.tmp && mv $s/state/web/peers.json.tmp $s/state/web/peers.json'"
assert_contains 'یونیت: محافظت فایل‌سیستم' "$svc" 'ProtectSystem=strict'
assert_contains 'یونیت: نوشتن فقط به state' "$svc" "ReadWritePaths=$s/state"
tmr=$(cat "$s/units/farshub-test-peers.timer")
assert_contains 'تایمر: OnBootSec' "$tmr" 'OnBootSec=15'
assert_contains 'تایمر: OnUnitActiveSec' "$tmr" 'OnUnitActiveSec=30'
assert_contains 'تایمر: WantedBy' "$tmr" 'WantedBy=timers.target'
assert_contains 'systemctl: daemon-reload' "$(cat "$SYSTEMD_LOG")" 'daemon-reload'
assert_contains 'systemctl: فعال‌سازی تایمر' "$(cat "$SYSTEMD_LOG")" \
  'enable --now farshub-test-peers.timer'
assert_contains 'نصب: پیام هر ۳۰ ثانیه' "$OUT" 'هر ۳۰ ثانیه'
assert_file 'نصب: peers.json پرایم شد' "$s/state/web/peers.json"
v=$(cat "$s/state/web/peers.json" | $PY -c 'import json,sys
d = json.load(sys.stdin)
print(d["side"])')
assert_eq 'پرایم: JSON معتبر با side=server' "$v" server
assert_file 'پرایم: state هم ساخته شد' "$s/state/peers-state.json"

# اجرای دوباره: بازنویسی، نه انباشت.
prun "$s" _peers-install server
assert_rc 'نصب دوباره: rc صفر' 0
n=$(ls "$s/units" | wc -l | tr -d ' ')
assert_eq 'نصب دوباره: همچنان فقط دو یونیت' "$n" 2

# --- خطاها -------------------------------------------------------------------
prun "$s" _peers-install bogus
assert_rc 'سمت نامعتبر: rc 2' 2
assert_contains 'سمت نامعتبر: پیام' "$ERR" 'سمت نامعتبر'

e=$(fixture); rm_on_exit="$rm_on_exit $e"
prun "$e" _peers-install server
assert_rc 'بدون کانفیگ: rc 1' 1
assert_contains 'بدون کانفیگ: پیام' "$ERR" 'کانفیگ نیست'

# --- panel-down: حذف تایمر و peers.json، ماندن تاریخچه -----------------------
p=$(fixture server); rm_on_exit="$rm_on_exit $p"
sed -i -e 's/^bind_addr = .*/bind_addr = "0.0.0.0:2083"/' \
       -e 's/^web_port = .*/web_port = 2060/' "$p/conf/server.toml"
printf 'ESTAB 0 0 10.0.0.1:2083 31.56.178.224:40198\n' >"$stub/ss.out"
prun "$p" _peers-install server
assert_rc 'panel-down: آماده‌سازی — نصب rc صفر' 0
assert_file 'panel-down: peers.json پیش از حذف هست' "$p/state/web/peers.json"

# وضعیت panel-up: side و پورت‌ها در panel.conf؛ سایت خالی — nginx روی ویندوز نیست.
printf 'side=server\npanel_port=8088\nweb_port=2060\nsite=\nlink=\n' \
  >"$p/state/panel.conf"

prun "$p" panel-down server
assert_rc 'panel-down: rc صفر' 0
assert_gone 'panel-down: یونیت سرویس حذف شد' "$p/units/farshub-test-peers.service"
assert_gone 'panel-down: یونیت تایمر حذف شد' "$p/units/farshub-test-peers.timer"
assert_gone 'panel-down: peers.json حذف شد' "$p/state/web/peers.json"
assert_file 'panel-down: peers-state.json ماند' "$p/state/peers-state.json"
assert_contains 'panel-down: غیرفعال‌سازی تایمر' "$(cat "$SYSTEMD_LOG")" \
  'disable --now farshub-test-peers.timer'
assert_contains 'panel-down: توقف سرویس peers' "$(cat "$SYSTEMD_LOG")" \
  'stop farshub-test-peers.service'
assert_contains 'panel-down: پیام حذف peers.json' "$OUT" 'peers.json حذف شد'
assert_contains 'panel-down: پیام پایانی تایمر' "$OUT" 'تایمر peers متوقف'
wp=$(sed -n 's/^web_port = //p' "$p/conf/server.toml")
assert_eq 'panel-down: web_port=0 شد' "$wp" 0
assert_gone 'panel-down: panel.conf حذف شد' "$p/state/panel.conf"

summary
