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
  if [ ! -d "$REPO/tests/web" ]; then
    printf '  رد شد — tests/web هنوز نیست\n'
  elif command -v node >/dev/null 2>&1; then
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
