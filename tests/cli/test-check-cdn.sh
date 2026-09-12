#!/bin/sh
# remote_addr پشت پروکسی کلادفلر = کانال کنترل بی‌پایان «unexpected EOF» و
# کاربرانی که وصل نمی‌شوند. check باید این را خطا بگیرد و status باید
# IP حل‌شده را نشان دهد. getent با یک استاب روی PATH شبیه‌سازی می‌شود.
set -u
. "$(dirname -- "$0")/../lib.sh"

d=$(fixture client)
stub=$(mktemp -d)
trap 'rm -rf "$d" "$stub"' EXIT
C="$d/conf/client.toml"

# موتور اجرا: استاب کافی است، check فقط وجودش را می‌بیند.
printf '#!/bin/sh\n' >"$d/libexec/farshub-core"
chmod +x "$d/libexec/farshub-core"

# استاب getent: IPهایی که باید برگرداند از STUB_IPS می‌آید (هر خط یکی).
cat >"$stub/getent" <<'EOF'
#!/bin/sh
[ "$1" = hosts ] && [ "$#" -ge 2 ] && printf '%s\n' "$STUB_IPS"
exit 0
EOF
chmod +x "$stub/getent"

# توکن پیش‌فرض CHANGE_ME خودش warn می‌سازد؛ درستش می‌کنیم تا فقط بررسی CDN
# سنجیده شود.
sed -i 's/^token = .*/token = "0123456789abcdef0123456789abcdef"/' "$C"
chmod 600 "$C"

# روی Git Bash ویندوز (noacl) chmod اثر ندارد و stat همیشه 644 می‌دهد؛
# آن‌جا بررسی دسترسی check یک warn ثابت اضافه می‌کند و کد خروجِ سناریوهای
# «سالم» ۱ می‌شود. روی لینوکس — جایی که farshub واقعاً اجرا می‌شود —
# انتظار واقعی 0 است.
perm=$(stat -c '%a' "$C" 2>/dev/null || echo '?')
case "$perm" in 600|400) clean_rc=0 ;; *) clean_rc=1 ;; esac

# اجرای farshub با استاب getent و همان انزوای محیطی envrun.
cdn() {   # $1=STUB_IPS؛ بقیه آرگومان‌ها به farshub
  _ips=$1; shift
  run env STUB_IPS="$_ips" PATH="$stub:$PATH" \
    FARSHUB_CONF_DIR="$d/conf" FARSHUB_LIBEXEC="$d/libexec" \
    FARSHUB_BIN_DIR="$d/bin" FARSHUB_UNIT_DIR="$d/units" \
    FARSHUB_LOG_DIR="$d/log" FARSHUB_STATE_DIR="$d/state" \
    FARSHUB_UNIT_PREFIX=farshub-test FARSHUB_SITE_NAME=farshub-test \
    sh "$FARSHUB" "$@"
}

# --- check: IP کلادفلر = خطا ----------------------------------------------
cdn '2606:4700:3034::ac43:8edd' check client
assert_rc 'CF v6 خطا داد' 1
assert_contains 'پیام CDN در check (v6)' "$OUT" 'CDN کلادفلر'

cdn '104.21.46.216' check client
assert_rc 'CF v4 خطا داد' 1
assert_contains 'پیام CDN در check (v4)' "$OUT" 'CDN کلادفلر'

cdn '2a06:98c1:3122::' check client
assert_rc 'CF v6 بازه‌ی دوم خطا داد' 1

# --- check: IP معمولی = سالم ----------------------------------------------
cdn '87.107.81.96' check client
assert_rc 'IP معمولی سالم' "$clean_rc"
assert_contains 'IP حل‌شده نمایش داده شد' "$OUT" 'remote_addr حل شد: 87.107.81.96'

two=$(printf '%s\n%s' 87.107.81.96 31.56.178.224)
cdn "$two" check client
assert_rc 'چند IP معمولی سالم' "$clean_rc"

# --- check: ws* عمداً از CDN عبور می‌کند، خطا نباید باشد -------------------
sed -i 's/^transport = .*/transport = "wssmux"/' "$C"
cdn '2606:4700:3034::ac43:8edd' check client
assert_rc 'wssmux پشت CDN خطا نیست' "$clean_rc"
assert_missing 'برای ws* پیام CDN نمی‌آید' "$OUT" 'CDN کلادفلر'
sed -i 's/^transport = .*/transport = "tcpmux"/' "$C"

# --- status: resolved نشان داده می‌شود -------------------------------------
cdn '2606:4700:3034::ac43:8edd' status client
assert_contains 'status آی‌پی حل‌شده را نشان می‌دهد' "$OUT" '2606:4700:3034::ac43:8edd'

# --- getent بی‌پاسخ: نه خطا، نه ادعای سلامت -------------------------------
cdn '' check client
assert_rc 'بدون پاسخ DNS خطا نیست' "$clean_rc"
assert_missing 'بدون پاسخ DNS پیام CDN نمی‌آید' "$OUT" 'CDN'

cdn '' status client
assert_missing 'بدون پاسخ DNS ادعای حل‌شدن نمی‌آید' "$OUT" 'resolved'

summary
