#!/bin/sh
# «peers» تنها پنجره‌ی مشاهده‌ی زنده‌ی تونل است: چه همتایی وصل است، از کِی، و
# در سمت سرور مصرف هر پورت. منابعش (ss و /data و /stats) همگی اختیاری‌اند، پس
# سه چیز جدا سنجیده می‌شود: داده‌ی درست وقتی منبع هست، داده‌ی خالی (نه خطا)
# وقتی منبع جواب نمی‌دهد، و دست‌نخوردنِ تاریخچه وقتی اصلاً چیزی دیده نمی‌شود.
# ss و curl و getent با استاب شبیه‌سازی می‌شوند؛ تاریخ‌ها با مقایسه‌ی رشته‌ای.
set -u
. "$(dirname -- "$0")/../lib.sh"

[ -n "$PY" ] || { printf '  %s — python لازم دارد\n' "$NAME"; exit 1; }

stub=$(mktemp -d)
rm_on_exit=''
trap 'rm -rf $rm_on_exit "$stub"' EXIT

# استاب ss: فقط فراخوانیِ pinned را می‌پذیرد و محتوای $SS_FILE را چاپ می‌کند.
cat >"$stub/ss" <<'EOF'
#!/bin/sh
[ "$1" = -H ] && [ "$2" = -tn ] && [ "$3" = state ] && [ "$4" = established ] || exit 1
cat "$SS_FILE"
EOF

# استاب curl: /data و /stats را از متغیر محیطی جواب می‌دهد. هر فراخوانی با
# آرگومانهای کاملش لاگ می‌شود تا هم «اصلاً صدا زده نشدن» سنجیده شود هم شکل
# خودِ فراخوانی.
cat >"$stub/curl" <<'EOF'
#!/bin/sh
for last; do :; done
printf '%s\n' "$*" >>"$CURL_LOG"
[ "${CURL_RC:-0}" = 0 ] || exit 1
case "$last" in
  */data)  printf '%s' "${DATA_RESP:-}" ;;
  */stats) printf '%s' "${STATS_RESP:-}" ;;
  *) exit 1 ;;
esac
EOF

# استاب getent — همان الگوی test-check-cdn.
cat >"$stub/getent" <<'EOF'
#!/bin/sh
[ "$1" = hosts ] && [ "$#" -ge 2 ] && printf '%s\n' "$STUB_IPS"
exit 0
EOF

chmod +x "$stub/ss" "$stub/curl" "$stub/getent" 2>/dev/null || true
: >"$stub/ss.out"

# اجرای farshub با استابها روی PATH و همان انزوای محیطی envrun. stderr جدا
# گرفته می‌شود تا «سکوت در موفقیت» هم سنجیده شود. پاسخ استابها از متغیرهای
# DATA_RESP و STATS_RESP و CURL_RC و STUB_IPS می‌آید.
prun() {                                   # $1=دایرکتوری fixture؛ بقیه → farshub
  _d=$1; shift
  : >"$stub/curl.log"
  OUT=$(env PATH="$stub:$PATH" SS_FILE="$stub/ss.out" \
    CURL_LOG="$stub/curl.log" CURL_RC="${CURL_RC:-0}" \
    DATA_RESP="${DATA_RESP:-}" STATS_RESP="${STATS_RESP:-}" STUB_IPS="${STUB_IPS:-}" \
    FARSHUB_CONF_DIR="$_d/conf" FARSHUB_LIBEXEC="$_d/libexec" \
    FARSHUB_BIN_DIR="$_d/bin" FARSHUB_UNIT_DIR="$_d/units" \
    FARSHUB_LOG_DIR="$_d/log" FARSHUB_STATE_DIR="$_d/state" \
    FARSHUB_UNIT_PREFIX=farshub-test FARSHUB_SITE_NAME=farshub-test \
    sh "$FARSHUB" "$@" 2>"$stub/stderr.txt")
  RC=$?
  ERR=$(cat "$stub/stderr.txt" 2>/dev/null)
  return 0
}

# بقایای پاسخ سناریوی قبلی نباید به بعدی نشت کند.
reset_stub_env() {
  DATA_RESP=''; STATS_RESP=''; CURL_RC=0; STUB_IPS=''
}

# عبارت پایتونی روی d (خروجی JSON) اجرا و نتیجه در JV می‌نشیند.
jv() {
  JV=$(printf '%s' "$OUT" | $PY -c 'import json,sys
d = json.load(sys.stdin)
print(eval(sys.argv[1]))' "$1")
}

# --- سرور: شمارش، پورت‌ها، مرتب‌سازی ---------------------------------------
reset_stub_env
s1=$(fixture server); rm_on_exit="$rm_on_exit $s1"
sed -i -e 's/^bind_addr = .*/bind_addr = "0.0.0.0:2083"/' \
       -e 's/^token = .*/token = "TOKENPEERS_0123456789abcdef0123"/' \
       -e 's/^web_port = .*/web_port = 2060/' "$s1/conf/server.toml"
run_stdin 'ports+=40199=40199
ports+=42099=35.207.200.69:443
' env FARSHUB_CONF_DIR="$s1/conf" sh "$FARSHUB" apply-config server
assert_rc 'ports در fixture سرور نصب شد' 0

# دو خط اول با ستون State، خط سوم بدون آن (نسخه‌های مختلف ss)؛ خط چهارم
# اتصالی به پورت دیگری است و نباید شمرده شود.
cat >"$stub/ss.out" <<'EOF'
ESTAB 0 0 10.0.0.1:2083 31.56.178.224:40198
ESTAB 0 0 10.0.0.1:2083 31.56.178.224:40199
0 0 10.0.0.1:2083 185.51.100.7:52310
ESTAB 0 0 10.0.0.1:443 9.9.9.9:54321
EOF
DATA_RESP='[{"Port":40199,"ReadableUsage":"201.88 MB"},{"Port":42099,"ReadableUsage":"12.00 KB"},{"Port":9999,"ReadableUsage":"1 B"}]'

prun "$s1" peers server
assert_rc 'سرور: rc صفر' 0
assert_eq 'سرور: stderr خالی' "$ERR" ''
v=$(printf '%s' "$OUT" | $PY -c 'import json,sys
json.load(sys.stdin)
print("valid")')
assert_eq 'سرور: JSON معتبر با json.load' "$v" valid
assert_eq 'سرور: اولین خط فقط {' "$(printf '%s' "$OUT" | head -n1)" '{'
jv 'd["side"]';         assert_eq 'سرور: side' "$JV" server
jv 'd["tunnel_port"]';  assert_eq 'سرور: tunnel_port' "$JV" 2083
jv 'd["transport"]';    assert_eq 'سرور: transport' "$JV" tcpmux
jv 'sorted(d.keys())';  assert_eq 'سرور: کلیدهای سرفصل' "$JV" \
  "['clients', 'generated_at', 'side', 'transport', 'tunnel_port']"
jv 'len(d["clients"])'; assert_eq 'سرور: دو کلاینت' "$JV" 2
jv 'd["clients"][0]["ip"]'; assert_eq 'سرور: مرتب‌سازی بر اساس IP' "$JV" 185.51.100.7
jv '[c for c in d["clients"] if c["ip"]=="31.56.178.224"][0]["connections"]'
assert_eq 'سرور: شمارش به‌ازای IP' "$JV" 2
jv '[p["port"] for p in d["clients"][0]["ports"]]'
assert_eq 'سرور: فقط پورت‌های کانفیگ' "$JV" '[40199, 42099]'
jv 'd["clients"][0]["ports"][0]["usage"]'
assert_eq 'سرور: usage پورت' "$JV" '201.88 MB'
jv 'sorted(d["clients"][0].keys())'; assert_eq 'سرور: کلیدهای کلاینت' "$JV" \
  "['connections', 'first_seen', 'ip', 'last_seen', 'ports']"
assert_missing 'سرور: پورت خارج از کانفیگ نمی‌آید' "$OUT" 9999
assert_missing 'سرور: کلاینتِ پورت دیگر نمی‌آید' "$OUT" '9.9.9.9'
assert_missing 'سرور: توکن هرگز چاپ نمی‌شود' "$OUT" TOKENPEERS
assert_contains 'سرور: شکل pinned برای tunnel_port' "$OUT" '  "tunnel_port": 2083,'
assert_contains 'سرور: شکل pinned برای مدخل پورت' "$OUT" '{ "port": 40199, "usage": "201.88 MB" }'
assert_contains 'سرور: curl با فراخوانی pinned روی /data' \
  "$(cat "$stub/curl.log")" '-s --max-time 3 http://127.0.0.1:2060/data'
assert_file 'سرور: state ساخته شد' "$s1/state/peers-state.json"

# فقط یک سمت نصب است → حدس سمت کار می‌کند
prun "$s1" peers
assert_rc 'سرور: حدس سمت' 0
jv 'd["side"]'; assert_eq 'سرور: حدس = server' "$JV" server

# --- سرور: ماندگاری first_seen و حذف همتای غایب ---------------------------
reset_stub_env
s2=$(fixture server); rm_on_exit="$rm_on_exit $s2"
sed -i 's/^bind_addr = .*/bind_addr = "0.0.0.0:2083"/' "$s2/conf/server.toml"
cat >"$s2/state/peers-state.json" <<'EOF'
{
"server/31.56.178.224": {"first_seen":"2020-01-01T00:00:00Z","last_seen":"2020-01-01T00:01:00Z"},
"server/1.1.1.1": {"first_seen":"2019-01-01T00:00:00Z","last_seen":"2019-01-01T00:01:00Z"}
}
EOF
printf 'ESTAB 0 0 10.0.0.1:2083 31.56.178.224:40198\n' >"$stub/ss.out"
t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
prun "$s2" peers server
t1=$(date -u +%Y-%m-%dT%H:%M:%SZ)
assert_rc 'سرور state: rc صفر' 0
assert_eq 'سرور state: stderr خالی' "$ERR" ''
jv 'd["clients"][0]["first_seen"]'
assert_eq 'سرور state: first_seen حفظ شد' "$JV" '2020-01-01T00:00:00Z'
jv 'd["clients"][0]["last_seen"]'
mid=$(printf '%s\n%s\n%s\n' "$t0" "$JV" "$t1" | LC_ALL=C sort | sed -n 2p)
assert_eq 'سرور state: last_seen بین قبل و بعد اجراست' "$mid" "$JV"
assert_missing 'سرور state: همتای غایب در خروجی نیست' "$OUT" '1.1.1.1'
st_content=$(cat "$s2/state/peers-state.json")
assert_missing 'سرور state: همتای غایب از فایل حذف شد' "$st_content" 'server/1.1.1.1'
assert_contains 'سرور state: فرمت pinned خط همتا' "$st_content" \
  "\"server/31.56.178.224\": {\"first_seen\":\"2020-01-01T00:00:00Z\",\"last_seen\":\"$JV\"}"
sv=$(cat "$s2/state/peers-state.json" | $PY -c 'import json,sys
d = json.load(sys.stdin)
print(d["server/31.56.178.224"]["first_seen"])')
assert_eq 'سرور state: فایل هم JSON معتبر با first_seen درست' "$sv" '2020-01-01T00:00:00Z'

# --- کلاینت: شمارش اتصال به سرور، /stats ------------------------------------
reset_stub_env
c1=$(fixture client); rm_on_exit="$rm_on_exit $c1"
sed -i -e 's/^remote_addr = .*/remote_addr = "87.107.81.96:2083"/' \
       -e 's/^token = .*/token = "TOKENPEER_0123456789abcdef9876"/' \
       -e 's/^web_port = .*/web_port = 2060/' "$c1/conf/client.toml"
i=1
while [ $i -le 9 ]; do
  printf '0 0 192.168.1.5:5100%s 87.107.81.96:2083\n' "$i"
  i=$((i + 1))
done >"$stub/ss.out"
printf 'ESTAB 0 0 192.168.1.5:52001 8.8.8.8:443\n'    >>"$stub/ss.out"
printf 'ESTAB 0 0 192.168.1.5:52002 87.107.81.96:443\n' >>"$stub/ss.out"
STUB_IPS='87.107.81.96'
STATS_RESP='{"tunnelStatus":"Connected (TCPMux)","cpuUsage":"8.98%","ramUsage":"174.70 MB","allConnections":"85"}'

prun "$c1" peers client
assert_rc 'کلاینت: rc صفر' 0
assert_eq 'کلاینت: stderr خالی' "$ERR" ''
jv 'd["side"]';                  assert_eq 'کلاینت: side' "$JV" client
jv 'd["transport"]';             assert_eq 'کلاینت: transport' "$JV" tcpmux
jv 'sorted(d.keys())';           assert_eq 'کلاینت: کلیدهای سرفصل' "$JV" \
  "['generated_at', 'server', 'side', 'transport']"
jv 'sorted(d["server"].keys())'; assert_eq 'کلاینت: کلیدهای server' "$JV" \
  "['connections', 'first_seen', 'host', 'last_seen', 'remote_addr', 'resolved_ip', 'tunnel_status']"
jv 'd["server"]["connections"]'; assert_eq 'کلاینت: ۹ اتصال' "$JV" 9
jv 'd["server"]["resolved_ip"]'; assert_eq 'کلاینت: resolved_ip' "$JV" 87.107.81.96
jv 'd["server"]["host"]';        assert_eq 'کلاینت: host' "$JV" 87.107.81.96
jv 'd["server"]["remote_addr"]'; assert_eq 'کلاینت: remote_addr' "$JV" '87.107.81.96:2083'
jv 'd["server"]["tunnel_status"]'; assert_eq 'کلاینت: tunnel_status' "$JV" 'Connected (TCPMux)'
assert_missing 'کلاینت: توکن هرگز چاپ نمی‌شود' "$OUT" TOKENPEER
assert_contains 'کلاینت: curl با فراخوانی pinned روی /stats' \
  "$(cat "$stub/curl.log")" '-s --max-time 3 http://127.0.0.1:2060/stats'

prun "$c1" peers
assert_rc 'کلاینت: حدس سمت' 0
jv 'd["side"]'; assert_eq 'کلاینت: حدس = client' "$JV" client

# --- کلاینت با دامنه: حل DNS، و نبود DNS ------------------------------------
reset_stub_env
c1d=$(fixture client); rm_on_exit="$rm_on_exit $c1d"
sed -i 's/^remote_addr = .*/remote_addr = "tunnel.example.com:2083"/' "$c1d/conf/client.toml"
printf 'ESTAB 0 0 192.168.1.5:51001 87.107.81.96:2083\n0 0 192.168.1.5:51002 31.56.178.224:2083\n' >"$stub/ss.out"
STUB_IPS='87.107.81.96'
prun "$c1d" peers client
assert_rc 'دامنه: rc صفر' 0
jv 'd["server"]["connections"]'; assert_eq 'دامنه: شمارش با IP حل‌شده' "$JV" 1
jv 'd["server"]["resolved_ip"]'; assert_eq 'دامنه: اولین IP پاسخ DNS' "$JV" 87.107.81.96
jv 'd["server"]["host"]';        assert_eq 'دامنه: host همان دامنه' "$JV" tunnel.example.com
assert_contains 'دامنه: کلید state با IP حل‌شده' \
  "$(cat "$c1d/state/peers-state.json")" 'client/87.107.81.96'

# DNS جواب ندهد: نه خطا، نه ادعای اتصال؛ state هم خالی می‌شود.
reset_stub_env
prun "$c1d" peers client
assert_rc 'دامنه بدون DNS: rc صفر' 0
jv 'd["server"]["connections"]'; assert_eq 'دامنه بدون DNS: صفر' "$JV" 0
jv 'd["server"]["resolved_ip"]'; assert_eq 'دامنه بدون DNS: resolved_ip خالی' "$JV" ''
jv 'd["server"]["first_seen"]';  assert_eq 'دامنه بدون DNS: first_seen خالی' "$JV" ''
assert_eq 'دامنه بدون DNS: state خالی شد' \
  "$(cat "$c1d/state/peers-state.json")" "$(printf '{\n}')"

# --- کلاینت: ماندگاری state در دو اجرا --------------------------------------
reset_stub_env
c2=$(fixture client); rm_on_exit="$rm_on_exit $c2"
sed -i 's/^remote_addr = .*/remote_addr = "87.107.81.96:2083"/' "$c2/conf/client.toml"
cat >"$c2/state/peers-state.json" <<'EOF'
{
"client/87.107.81.96": {"first_seen":"2020-01-01T00:00:00Z","last_seen":"2020-01-01T00:01:00Z"}
}
EOF
printf 'ESTAB 0 0 192.168.1.5:51001 87.107.81.96:2083\n' >"$stub/ss.out"
t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
prun "$c2" peers client
t1=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jv 'd["server"]["first_seen"]'
assert_eq 'کلاینت state: first_seen حفظ شد (اجرای ۱)' "$JV" '2020-01-01T00:00:00Z'
jv 'd["server"]["last_seen"]'
mid=$(printf '%s\n%s\n%s\n' "$t0" "$JV" "$t1" | LC_ALL=C sort | sed -n 2p)
assert_eq 'کلاینت state: last_seen بین قبل و بعد اجراست' "$mid" "$JV"
prun "$c2" peers client
jv 'd["server"]["first_seen"]'
assert_eq 'کلاینت state: first_seen حفظ شد (اجرای ۲)' "$JV" '2020-01-01T00:00:00Z'
assert_contains 'کلاینت state: کلید درست در فایل' \
  "$(cat "$c2/state/peers-state.json")" '"client/87.107.81.96": {"first_seen":"2020-01-01T00:00:00Z"'

# --- web_port=0: اصلاً curl صدا زده نمی‌شود -----------------------------------
reset_stub_env
s5=$(fixture server); rm_on_exit="$rm_on_exit $s5"
sed -i 's/^bind_addr = .*/bind_addr = "0.0.0.0:2083"/' "$s5/conf/server.toml"
printf 'ESTAB 0 0 10.0.0.1:2083 31.56.178.224:40198\n' >"$stub/ss.out"
# پاسخ‌ها عمداً پر می‌مانند؛ باید نادیده بمانند چون curl اصلاً اجرا نمی‌شود.
DATA_RESP='[{"Port":40199,"ReadableUsage":"201.88 MB"}]'
STATS_RESP='{"tunnelStatus":"Connected (TCPMux)"}'
prun "$s5" peers server
assert_rc 'web_port=0 سرور: rc صفر' 0
assert_eq 'web_port=0 سرور: curl صدا زده نشد' "$(cat "$stub/curl.log")" ''
jv 'd["clients"][0]["ports"]'; assert_eq 'web_port=0 سرور: ports خالی' "$JV" '[]'

c5=$(fixture client); rm_on_exit="$rm_on_exit $c5"
sed -i 's/^remote_addr = .*/remote_addr = "87.107.81.96:2083"/' "$c5/conf/client.toml"
prun "$c5" peers client
assert_rc 'web_port=0 کلاینت: rc صفر' 0
assert_eq 'web_port=0 کلاینت: curl صدا زده نشد' "$(cat "$stub/curl.log")" ''
jv 'd["server"]["tunnel_status"]'; assert_eq 'web_port=0 کلاینت: unknown' "$JV" unknown

# --- خرابی منابع: HTML، شکست curl، ss خالی، ss غایب ---------------------------
reset_stub_env
s6=$(fixture server); rm_on_exit="$rm_on_exit $s6"
sed -i -e 's/^bind_addr = .*/bind_addr = "0.0.0.0:2083"/' \
       -e 's/^web_port = .*/web_port = 2060/' "$s6/conf/server.toml"
printf 'ESTAB 0 0 10.0.0.1:2083 31.56.178.224:40198\n' >"$stub/ss.out"

# sniffer خاموش → موتور به‌جای JSON، HTML می‌دهد؛ همان لیست خالی است.
DATA_RESP='<html><body>engine panel</body></html>'
prun "$s6" peers server
assert_rc 'HTML در /data: rc صفر' 0
assert_eq 'HTML در /data: stderr خالی' "$ERR" ''
jv 'd["clients"][0]["ports"]'; assert_eq 'HTML در /data: ports خالی' "$JV" '[]'

CURL_RC=1
prun "$s6" peers server
assert_rc 'شکست curl در سمت سرور: rc صفر' 0
jv 'd["clients"][0]["ports"]'; assert_eq 'شکست curl: ports خالی' "$JV" '[]'

c6=$(fixture client); rm_on_exit="$rm_on_exit $c6"
sed -i -e 's/^remote_addr = .*/remote_addr = "87.107.81.96:2083"/' \
       -e 's/^web_port = .*/web_port = 2060/' "$c6/conf/client.toml"
STATS_RESP='<html>not json</html>'
prun "$c6" peers client
assert_rc 'HTML در /stats: rc صفر' 0
jv 'd["server"]["tunnel_status"]'; assert_eq 'HTML در /stats: unknown' "$JV" unknown
CURL_RC=1
prun "$c6" peers client
assert_rc 'شکست curl در سمت کلاینت: rc صفر' 0
jv 'd["server"]["tunnel_status"]'; assert_eq 'شکست curl کلاینت: unknown' "$JV" unknown

# ss خالی = مشاهده‌ی معتبرِ بدون همتا: خروجی خالی و state پاک.
reset_stub_env
: >"$stub/ss.out"
prun "$s6" peers server
assert_rc 'ss خالی: rc صفر' 0
jv 'd["clients"]'; assert_eq 'ss خالی: clients خالی' "$JV" '[]'
assert_eq 'ss خالی: state خالی شد' \
  "$(cat "$s6/state/peers-state.json")" "$(printf '{\n}')"
prun "$c6" peers client
jv 'd["server"]["connections"]'; assert_eq 'ss خالی کلاینت: صفر' "$JV" 0

# ss غایب (PATH بدون استاب — پیش‌فرض همین ماشین): هیچ مشاهده‌ای نیست؛ state
# دست نمی‌خورد. پاک کردن تاریخچه به‌بهانه‌ی ناتوانی در دیدن، بدترین حالت است.
s6b=$(fixture server); rm_on_exit="$rm_on_exit $s6b"
sed -i 's/^bind_addr = .*/bind_addr = "0.0.0.0:2083"/' "$s6b/conf/server.toml"
cat >"$s6b/state/peers-state.json" <<'EOF'
{
"server/31.56.178.224": {"first_seen":"2020-01-01T00:00:00Z","last_seen":"2020-01-01T00:01:00Z"}
}
EOF
before=$(cat "$s6b/state/peers-state.json")
envrun "$s6b" peers server
assert_rc 'ss غایب: rc صفر' 0
jv 'd["clients"]'; assert_eq 'ss غایب: clients خالی' "$JV" '[]'
assert_eq 'ss غایب: state بایت‌به‌بایت دست‌نخورده' \
  "$(cat "$s6b/state/peers-state.json")" "$before"

# --- آرگومان‌ها و خطاها -------------------------------------------------------
reset_stub_env
prun "$s1" peers bogus
assert_rc 'سمت نامعتبر: rc 2' 2
assert_contains 'سمت نامعتبر: پیام' "$ERR" 'سمت نامعتبر'

e=$(fixture); rm_on_exit="$rm_on_exit $e"
prun "$e" peers
assert_rc 'بدون هیچ کانفیگ: rc 1' 1

b=$(fixture); rm_on_exit="$rm_on_exit $b"
cp "$REPO/configs/server.toml" "$b/conf/server.toml"
cp "$REPO/configs/client.toml" "$b/conf/client.toml"
prun "$b" peers
assert_rc 'هر دو سمت نصب و سمت نگفته: rc 1' 1
assert_contains 'هر دو سمت: راهنمای صریح' "$ERR" 'server|client'

s7=$(fixture server); rm_on_exit="$rm_on_exit $s7"
sed -i '/^bind_addr = /d' "$s7/conf/server.toml"
prun "$s7" peers server
assert_rc 'سرور بدون bind_addr: rc 1' 1
assert_contains 'سرور بدون bind_addr: پیام' "$ERR" 'bind_addr'

# --- راهنما -------------------------------------------------------------------
fh help
assert_rc 'help: rc صفر' 0
assert_contains 'ردیف peers در راهنما هست' "$OUT" 'peers'
assert_contains 'معنای first_seen در راهنما آمده' "$OUT" 'first_seen'

summary
