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
